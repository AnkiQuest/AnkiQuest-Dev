// A stand-in for the gh CLI, for tests/nightly-release.test.ts: the release
// and tag calls publish.sh makes, against a JSON state file ($FAKE_STATE).
// A fault in the state fails the first `times` calls whose arguments contain
// `match`, before or (`after`) once the call took effect, as a 5xx does.
// With `lag`, GitHub turns a deleted tag's release into a draft only that
// many calls later, as it does in the background.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';

type Release = {id: number; tag_name: string; name: string; body: string; draft: boolean; prerelease: boolean; assets: string[]};
type Fault = {match: string; times: number; after?: boolean};
type Untag = {id: number; at: number};
type State = {tags: Record<string, string>; releases: Release[]; next: number; faults: Fault[]; calls: string[]; lag?: number; untags?: Untag[]};

const file = process.env.FAKE_STATE!;
const state: State = JSON.parse(fs.readFileSync(file, 'utf8'));
const args = process.argv.slice(2);
const line = args.join(' ');
state.calls.push(line);

// The background drafts of deleted tags' releases that are due by this call.
// They apply to the release even if it was published again since.
for (const untag of (state.untags ?? []).filter(u => u.at <= state.calls.length)) {
  const r = state.releases.find(x => x.id === untag.id);
  if (r) {
    r.draft = true;
  }
}
state.untags = (state.untags ?? []).filter(u => u.at > state.calls.length);

// The value after a flag, and the -f/-F fields of an API call.
function flag(name: string): string | undefined {
  const at = args.indexOf(name);
  return at < 0 ? undefined : args[at + 1];
}
function fields(): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  args.forEach((arg, at) => {
    if (arg !== '-f' && arg !== '-F') {
      return;
    }
    const [key, ...rest] = args[at + 1].split('=');
    const value = rest.join('=');
    out[key] = arg === '-F' && (value === 'true' || value === 'false') ? value === 'true' : value;
  });
  return out;
}

function finish(code: number, out?: unknown) {
  fs.writeFileSync(file, JSON.stringify(state));
  if (out !== undefined && code === 0) {
    const jq = flag('--jq');
    const text = JSON.stringify(out);
    process.stdout.write(jq ? execFileSync('jq', ['-r', jq], {input: text, encoding: 'utf8'}) : text + '\n');
  }
  if (code !== 0) {
    process.stderr.write(`fake gh: ${line} failed (HTTP ${code})\n`);
  }
  process.exit(code === 0 ? 0 : 1);
}

const fault = state.faults.find(f => f.times > 0 && line.includes(f.match));
if (fault) {
  fault.times -= 1;
}
if (fault && !fault.after) {
  finish(502);
}

const byTag = (tag: string) => state.releases.find(r => r.tag_name === tag && !r.draft);
const method = flag('-X') ?? (args.includes('-f') || args.includes('-F') ? 'POST' : 'GET');
const path = args.slice(1).find(a => a.startsWith('repos/'))?.replace(/^repos\/[^/]+\/[^/]+\//, '');

// Runs the call; returns the HTTP status and the response.
function run(): [number, unknown?] {
  if (args[0] === 'api' && path?.startsWith('releases?') && method === 'GET') {
    return [200, [...state.releases].reverse()];
  }
  if (args[0] === 'api' && path === 'releases' && method === 'POST') {
    const f = fields();
    const tag = f.tag_name as string;
    if (byTag(tag)) {
      return [422];
    }
    state.tags[tag] ??= f.target_commitish as string;
    const release = {id: state.next++, tag_name: tag, name: f.name as string, body: '', draft: false, prerelease: f.prerelease as boolean, assets: []};
    state.releases.push(release);
    return [201, release];
  }
  const release = path?.match(/^releases\/(\d+)$/);
  if (args[0] === 'api' && release && method === 'GET') {
    const r = state.releases.find(x => x.id === Number(release[1]));
    return r ? [200, r] : [404];
  }
  if (args[0] === 'api' && release && method === 'PATCH') {
    const r = state.releases.find(x => x.id === Number(release[1]));
    if (!r) {
      return [404];
    }
    const f = fields();
    Object.assign(r, {tag_name: f.tag_name, name: f.name, body: f.body, draft: f.draft, prerelease: f.prerelease});
    if (!r.draft) {
      state.tags[r.tag_name] ??= f.target_commitish as string;
    }
    return [200, r];
  }
  const ref = path?.match(/^git\/refs?\/tags\/(.+)$/);
  if (args[0] === 'api' && ref && method === 'DELETE') {
    if (!(ref[1] in state.tags)) {
      return [422];
    }
    delete state.tags[ref[1]];
    // GitHub turns the tag's release into an untagged draft, at once or `lag` calls later.
    for (const r of state.releases.filter(x => x.tag_name === ref[1])) {
      if (state.lag) {
        state.untags = [...(state.untags ?? []), {id: r.id, at: state.calls.length + state.lag}];
        continue;
      }
      Object.assign(r, {draft: true, tag_name: `untagged-${r.id}`});
    }
    return [204];
  }
  if (args[0] === 'api' && ref && method === 'GET') {
    return ref[1] in state.tags ? [200, {object: {sha: state.tags[ref[1]]}}] : [404];
  }
  // gh's release commands also find a draft by the tag it names.
  const r = byTag(args[2]) ?? state.releases.find(x => x.tag_name === args[2]);
  if (args[0] === 'release' && !r) {
    return [404];
  }
  if (args[0] === 'release' && args[1] === 'view') {
    return [200, {assets: r!.assets.map(name => ({name}))}];
  }
  if (args[0] === 'release' && args[1] === 'upload') {
    const names = args.slice(3).filter(a => !a.startsWith('--')).map(a => a.split('/').pop()!);
    const clash = names.find(n => r!.assets.includes(n));
    if (clash && !args.includes('--clobber')) {
      return [422];
    }
    r!.assets = [...r!.assets.filter(a => !names.includes(a)), ...names];
    return [0];
  }
  if (args[0] === 'release' && args[1] === 'delete-asset') {
    r!.assets = r!.assets.filter(a => a !== args[3]);
    return [0];
  }
  throw new Error(`fake gh: unexpected call: ${line}`);
}

const [status, out] = run();
finish(fault?.after ? 504 : status < 300 ? 0 : status, out);

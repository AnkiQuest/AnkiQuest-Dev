// The nightly-release action (.github/actions/nightly-release): publish.sh
// against a fake gh (tests/fake-gh.ts) that keeps releases and tags in a
// file and fails calls the way the release API's 5xx answers do.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const PUBLISH = path.join(root, '.github', 'actions', 'nightly-release', 'publish.sh');
const FAKE = path.join(root, 'tests', 'fake-gh.ts');
const OLD = 'a'.repeat(40);
const NEW = 'b'.repeat(40);

type Release = {id: number; tag_name: string; name: string; body: string; draft: boolean; prerelease: boolean; assets: string[]};
type Fault = {match: string; times: number; after?: boolean};
type State = {tags: Record<string, string>; releases: Release[]; next: number; faults: Fault[]; calls: string[]; lag?: number};

// A previous nightly at OLD with the given assets.
function published(assets: string[]): Partial<State> {
  return {
    tags: {nightly: OLD},
    releases: [{id: 1, tag_name: 'nightly', name: 'Old', body: 'old', draft: false, prerelease: true, assets}],
    next: 2,
  };
}

// Runs publish.sh for NEW with files a.apk and nightly.json; returns its
// exit status and the fake's state afterwards.
function publish(start: Partial<State>): {status: number | null; state: State; stderr: string} {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nightly-release-'));
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'gh'), `#!/bin/sh\nexec node --experimental-strip-types --no-warnings ${FAKE} "$@"\n`, {mode: 0o755});
  for (const name of ['a.apk', 'nightly.json']) {
    fs.writeFileSync(path.join(dir, name), name);
  }
  const state = path.join(dir, 'state.json');
  fs.writeFileSync(state, JSON.stringify({tags: {}, releases: [], next: 1, faults: [], calls: [], ...start}));
  const run = spawnSync('bash', [PUBLISH], {
    cwd: dir,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      FAKE_STATE: state,
      RETRY_WAITS: '0 0 0',
      GITHUB_REPOSITORY: 'AnkiQuest/Test',
      TAG: 'nightly',
      TITLE: 'Test nightly',
      NOTES: `Built from ${NEW}.`,
      NOTES_FILE: '',
      FILES: 'a.*\nnightly.json\n',
      TARGET: NEW,
    },
  });
  const result = {status: run.status, state: JSON.parse(fs.readFileSync(state, 'utf8')) as State, stderr: run.stderr};
  fs.rmSync(dir, {recursive: true});
  return result;
}

// The one nightly release, published at NEW with the new title, notes and files.
function current(state: State) {
  assert.equal(state.releases.length, 1, JSON.stringify(state.releases));
  const [release] = state.releases;
  assert.deepEqual(
    {tag: state.tags.nightly, tag_name: release.tag_name, name: release.name, body: release.body, draft: release.draft, prerelease: release.prerelease},
    {tag: NEW, tag_name: 'nightly', name: 'Test nightly', body: `Built from ${NEW}.`, draft: false, prerelease: true},
  );
  assert.deepEqual([...release.assets].sort(), ['a.apk', 'nightly.json']);
}

test('creates the release when there is none', () => {
  const run = publish({});
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
});

test('updates the release in place, replaces its files and drops old ones', () => {
  const run = publish(published(['a.apk', 'nightly.json', 'old.apk']));
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
  assert.equal(run.state.releases[0].id, 1);
  assert.ok(!run.state.calls.some(c => c.startsWith('release delete ')), 'the release is never deleted');
});

test('retries API calls that fail with 5xx', () => {
  const run = publish({
    ...published(['a.apk', 'old.apk']),
    faults: [
      {match: 'releases?per_page', times: 2},
      {match: '-X DELETE', times: 1},
      {match: '-X PATCH', times: 1, after: true},
      {match: 'release upload', times: 2},
      {match: 'delete-asset', times: 1},
    ],
  });
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
  assert.ok(run.state.faults.every(f => f.times === 0), 'every fault was hit');
});

test('a create that timed out after it took effect makes no second release', () => {
  const run = publish({faults: [{match: 'api repos/AnkiQuest/Test/releases -f', times: 1, after: true}]});
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
});

test('picks up the untagged draft a failed run left behind', () => {
  const left = published(['a.apk']);
  left.tags = {};
  left.releases![0] = {...left.releases![0], tag_name: 'untagged-1', draft: true};
  const run = publish(left);
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
});

test('a release GitHub drafts after the tag moved ends published', () => {
  for (const lag of [1, 2, 3, 4, 5, 6]) {
    const run = publish({...published(['a.apk', 'nightly.json']), lag});
    assert.equal(run.status, 0, run.stderr);
    current(run.state);
  }
});

test('a rerun at the same commit keeps the tag', () => {
  const start = published(['a.apk', 'nightly.json']);
  start.tags = {nightly: NEW};
  const run = publish(start);
  assert.equal(run.status, 0, run.stderr);
  current(run.state);
  assert.ok(!run.state.calls.some(c => c.includes('-X DELETE')), 'the tag is not deleted');
});

test('fails once the retries are used up', () => {
  const run = publish({...published(['a.apk']), faults: [{match: 'release upload', times: 4}]});
  assert.notEqual(run.status, 0);
});

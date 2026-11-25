// The shared label set in labels.json is valid and holds every label the
// reusable workflows and Dependabot apply. needs-review.cjs keeps "Needs
// Review" on pull requests that wait on a reviewer, from the status and sweep
// jobs. The caller, ankiquest-labels.yml, is the one every repository copies.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createRequire} from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

interface Label {name: string; color: string; description: string; aliases: string[]}

const root = path.resolve(import.meta.dirname, '..');
const workflows = path.join(root, '.github', 'workflows');
const read = (file: string) => fs.readFileSync(path.join(workflows, file), 'utf8');
const labels = JSON.parse(fs.readFileSync(path.join(root, 'labels.json'), 'utf8')) as Label[];

// The rule, and where the jobs check it out: AnkiQuest-Dev's master in
// ./ankiquest-dev of the calling repository.
const RULE = path.join(root, '.github', 'scripts', 'needs-review.cjs');
const CHECKOUT = './ankiquest-dev/';
const nodeRequire = createRequire(import.meta.url);
const {State, reviewState} = nodeRequire(RULE);

// GitHub's limits for a label, and the labels Dependabot adds by default for
// the ecosystems in .github/dependabot.yml.
const COLOR = /^[0-9a-f]{6}$/;
const MAX_DESCRIPTION = 100;
const DEPENDABOT = ['dependencies', 'rust', 'github_actions'];

// The caller every repository copies, and the reusable pull request workflow.
const CALLER = 'ankiquest-labels.yml';
const PULL_REQUESTS = 'pr-labels.yml';

// A workflow that adds, removes or creates labels.
const LABELLING = /addLabels|removeLabel|actions\/labeler@|\$GITHUB_REPOSITORY\/labels/;

// Workflows here that apply labels.
function labellingWorkflows(): string[] {
  return fs.readdirSync(workflows).filter(file => /\.ya?ml$/.test(file) && LABELLING.test(read(file)));
}

// Area labels are the top-level keys of this repository's labeler config,
// which the area job of pr-labels.yml requires.
function labelerNames(): string[] {
  const text = fs.readFileSync(path.join(root, '.github', 'labeler.yml'), 'utf8');
  return [...text.matchAll(/^([A-Za-z_][^:\n]*):$/gm)].map(match => match[1]);
}

// The conflict scan, an action so the calling job keeps the name "scan".
const CONFLICT_SCAN = path.join(root, '.github', 'actions', 'conflict-scan', 'action.yml');

// Label names in the shared workflow scripts: constants and add/remove calls.
function workflowNames(): string[] {
  const names: string[] = [];
  const texts = [...labellingWorkflows().map(read), ...[CONFLICT_SCAN, RULE].map(file => fs.readFileSync(file, 'utf8'))];
  for (const text of texts) {
    for (const match of text.matchAll(/(?:[A-Z]+ = |add\(|remove\()'([^']+)'/g)) {
      names.push(match[1]);
    }
  }
  return names;
}

// The github-script body of one job in a workflow, dedented.
function jobScript(file: string, job: string): string {
  const text = read(file);
  const start = text.indexOf(`\n  ${job}:\n`);
  assert.ok(start >= 0, `${file} has no job ${job}`);
  const block = text.slice(start).match(/\n( +)script: \|\n((?:\1  .*\n|\s*\n)+)/);
  assert.ok(block, `${file} job ${job} has no script`);
  const indent = block[1].length + 2;
  return block[2].split('\n').map(line => line.slice(indent)).join('\n');
}

interface Call {action: string; labels: string[]; number?: number}
// A review's commit is the pull request's head unless it says otherwise.
interface Review {login: string; state: string; association?: string; commit?: string}

// One pull request as the status script sees it: the event that ran it and
// the pull request and reviews the GitHub API returns.
interface Pull {
  event?: string;
  action: string;
  draft?: boolean;
  state?: string;
  labels?: string[];
  reviews?: Review[];
  fork?: boolean;
  number?: number;
}

// Requires the rule from the checkout path the jobs use.
function jobRequire(file: string): unknown {
  assert.ok(file.startsWith(CHECKOUT), `required ${file} outside the AnkiQuest-Dev checkout`);
  return nodeRequire(path.join(root, file.slice(CHECKOUT.length)));
}

const REPO = {owner: 'AnkiQuest', repo: 'test'};
const AUTHOR = 'author';
const HEAD = 'head-sha';

// A pull request and its reviews as the GitHub API returns them.
function pullRequest(pull: Pull, association = 'MEMBER') {
  const labels = (pull.labels ?? []).map(name => ({name}));
  const head = {sha: HEAD, repo: {full_name: pull.fork ? 'someone/test' : 'AnkiQuest/test'}};
  const pr = {
    number: pull.number ?? 1, state: pull.state ?? 'open', draft: pull.draft ?? false, labels, head,
    user: {login: AUTHOR}, author_association: association,
  };
  const reviews = (pull.reviews ?? []).map((review, index) => ({
    id: index, user: {login: review.login}, state: review.state,
    author_association: review.association ?? 'MEMBER', commit_id: review.commit ?? HEAD,
  }));
  return {pr, reviews};
}

// Runs one job's github-script against a fake GitHub API serving `pulls`,
// for an event on the first of them, and returns the label changes it makes.
async function runAll(job: string, pulls: Pull[], association = 'MEMBER'): Promise<Call[]> {
  const calls: Call[] = [];
  const pull = pulls[0] ?? {action: ''};
  const served = pulls.map(item => pullRequest(item, association));
  const find = (number: number) => served.find(item => item.pr.number === number)!;
  const issues = {
    addLabels: async (args: {issue_number: number; labels: string[]}) => {
      calls.push({action: 'add', labels: args.labels, ...number(args.issue_number)});
    },
    removeLabel: async (args: {issue_number: number; name: string}) => {
      calls.push({action: 'remove', labels: [args.name], ...number(args.issue_number)});
    },
  };
  // Calls name their pull request only when the job serves several.
  const number = (issue: number) => (pulls.length > 1 ? {number: issue} : {});
  const api = {
    get: async (args: {pull_number: number}) => {
      assert.ok(!(pull.event === 'pull_request_review' && pull.fork), 'read-only run called the API');
      return {data: find(args.pull_number).pr};
    },
    list: async (args: {state: string}) => {
      assert.equal(args.state, 'open');
      return {data: served.map(item => item.pr).filter(pr => pr.state === 'open')};
    },
    listReviews: async (args: {pull_number: number}) => ({data: find(args.pull_number).reviews}),
  };
  const paginate = async (method: (args: never) => Promise<{data: unknown[]}>, args: never) => (await method(args)).data;
  const context = {
    repo: REPO,
    eventName: pull.event ?? 'pull_request_target',
    payload: {action: pull.action, pull_request: served[0]?.pr},
  };
  const core = {info: () => {}, notice: () => {}};
  const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
  const script = jobScript(PULL_REQUESTS, job);
  const github = {rest: {issues, pulls: api}, paginate};
  await new AsyncFunction('github', 'context', 'core', 'require', script)(github, context, core, jobRequire);
  return calls;
}

const run = (job: string, pull: Pull, association = 'MEMBER') => runAll(job, [pull], association);

const status = (pull: Pull) => run('status', pull);

test('labels.json entries are well formed and unique ignoring case', () => {
  const seen = new Set<string>();
  for (const label of labels) {
    assert.deepEqual(Object.keys(label).sort(), ['aliases', 'color', 'description', 'name'], label.name);
    assert.match(label.color, COLOR, label.name);
    assert.ok(label.description.length <= MAX_DESCRIPTION, label.name);
    for (const name of [label.name, ...label.aliases]) {
      const key = name.toLowerCase();
      assert.ok(!seen.has(key), `${name} appears twice`);
      seen.add(key);
    }
  }
});

test('labels.json holds every label the workflows apply, spelled the same', () => {
  const names = new Set(labels.map(label => label.name));
  const used = [...workflowNames(), ...labelerNames(), ...DEPENDABOT];
  assert.ok(workflowNames().length > 0);
  for (const name of used) {
    assert.ok(names.has(name), `${name} is missing from labels.json`);
  }
});

test('the label workflows are reusable and the caller calls each of them', () => {
  const called = [...read(CALLER).matchAll(/AnkiQuest-Dev\/\.github\/workflows\/(\S+\.yml)@master/g)].map(match => match[1]);
  const reusable = [...labellingWorkflows()].filter(file => file !== CALLER);
  assert.deepEqual([...called].sort(), [...reusable].sort());
  for (const file of reusable) {
    assert.match(read(file), /^on:\n {2}workflow_call:\n/m, file);
  }
});

test('the caller runs the conflict scan in a job named scan', () => {
  // The rulesets require this exact check name.
  const job = read(CALLER).match(/\n {2}scan:\n((?: {4}.*\n| {6}.*\n)+)/);
  assert.ok(job, `${CALLER} has no job scan`);
  assert.match(job[1], /uses: AnkiQuest\/AnkiQuest-Dev\/\.github\/actions\/conflict-scan@master/);
  assert.doesNotMatch(job[1], /^ {4}uses:/m);
});

// The `on:` types of one trigger in the pull request labels workflow; the
// trigger's line may end in a comment, such as a zizmor ignore.
function eventTypes(event: string): string[] {
  const types = read(CALLER).match(new RegExp(`${event}:(?: #.*)?\\n\\s+types: \\[([^\\]]+)\\]`));
  assert.ok(types, `no ${event} types`);
  return types[1].split(/,\s*/);
}

// The settings of one job's concurrency block.
function jobConcurrency(job: string): {group?: string; cancel?: string} {
  const text = read(PULL_REQUESTS);
  const block = text.slice(text.indexOf(`\n  ${job}:\n`)).match(/\n {4}concurrency:\n((?: {6}.*\n)+)/);
  assert.ok(block, `job ${job} has no concurrency`);
  const value = (key: string) => block[1].match(new RegExp(`^ {6}${key}: (.*)$`, 'm'))?.[1];
  return {group: value('group'), cancel: value('cancel-in-progress')};
}

const add = {action: 'add', labels: ['Needs Review']};
const remove = {action: 'remove', labels: ['Needs Review']};
const approved = {login: 'reviewer', state: 'APPROVED'};

test('pull request labels run on every draft, ready, push and review change', () => {
  for (const type of ['opened', 'reopened', 'synchronize', 'ready_for_review', 'converted_to_draft', 'closed']) {
    assert.ok(eventTypes('pull_request_target').includes(type), type);
  }
  for (const type of ['submitted', 'dismissed']) {
    assert.ok(eventTypes('pull_request_review').includes(type), type);
  }
});

test('Needs Review follows the draft state', async () => {
  assert.deepEqual(await status({action: 'opened'}), [add]);
  assert.deepEqual(await status({action: 'opened', draft: true}), []);

  // A pull request opened as a draft gets the label once it is ready.
  assert.deepEqual(await status({action: 'ready_for_review'}), [add]);
  assert.deepEqual(await status({action: 'ready_for_review', labels: ['needs review']}), []);
  assert.deepEqual(await status({action: 'converted_to_draft', draft: true, labels: ['Needs Review']}), [remove]);
  assert.deepEqual(await status({action: 'closed', state: 'closed', labels: ['Needs Review', 'Has Conflicts']}),
    [remove, {action: 'remove', labels: ['Has Conflicts']}]);
});

test('an approval removes Needs Review', async () => {
  const review = {event: 'pull_request_review', action: 'submitted', labels: ['Needs Review']};
  assert.deepEqual(await status({...review, reviews: [approved]}), [remove]);
  assert.deepEqual(await status({...review, reviews: [{login: 'reviewer', state: 'COMMENTED'}]}), []);

  // A comment after an approval keeps it.
  assert.deepEqual(await status({...review, reviews: [approved, {login: 'reviewer', state: 'COMMENTED'}]}), [remove]);

  // An approved pull request opened or reopened gets no label.
  assert.deepEqual(await status({action: 'reopened', reviews: [approved]}), []);
});

test('only an approval by another member counts', async () => {
  const review = {event: 'pull_request_review', action: 'submitted', labels: ['Needs Review']};
  assert.deepEqual(await status({...review, reviews: [{login: AUTHOR, state: 'APPROVED'}]}), []);
  assert.deepEqual(await status({...review, reviews: [{login: 'visitor', state: 'APPROVED', association: 'NONE'}]}), []);
  assert.deepEqual(await status({...review, reviews: [{login: 'reviewer', state: 'APPROVED', association: 'COLLABORATOR'}]}), [remove]);
});

test('a push keeps an approval that was not dismissed', async () => {
  assert.deepEqual(await status({action: 'synchronize', reviews: [approved]}), []);
  assert.deepEqual(await status({action: 'synchronize', labels: ['Needs Review'], reviews: [approved]}), [remove]);

  // Branch protection dismisses stale approvals by setting their state.
  assert.deepEqual(await status({action: 'synchronize', reviews: [{login: 'reviewer', state: 'DISMISSED'}]}), [add]);
  assert.deepEqual(await status({event: 'pull_request_review', action: 'dismissed', reviews: [{login: 'reviewer', state: 'DISMISSED'}]}), [add]);
  assert.deepEqual(await status({action: 'synchronize'}), [add]);
});

test('changes requested on the current head wait on the author', async () => {
  const review = {event: 'pull_request_review', action: 'submitted'};
  const changes = {login: 'other', state: 'CHANGES_REQUESTED'};
  assert.deepEqual(await status({...review, reviews: [changes]}), []);
  assert.deepEqual(await status({...review, labels: ['Needs Review'], reviews: [changes]}), [remove]);

  // A change request after the last approval outweighs it.
  assert.deepEqual(await status({...review, labels: ['Needs Review'], reviews: [approved, changes]}), [remove]);

  // An approval after a change request approves.
  assert.deepEqual(await status({...review, labels: ['Needs Review'], reviews: [changes, approved]}), [remove]);
  const asked = {login: 'reviewer', state: 'CHANGES_REQUESTED'};
  assert.deepEqual(await status({...review, labels: ['Needs Review'], reviews: [asked, approved]}), [remove]);
});

test('a push after a change request needs review again', async () => {
  const older = {login: 'other', state: 'CHANGES_REQUESTED', commit: 'older-sha'};
  assert.deepEqual(await status({action: 'synchronize', reviews: [older]}), [add]);
  assert.deepEqual(await status({action: 'synchronize', reviews: [approved, older]}), [add]);

  // One member's change request on the head is enough to wait on the author.
  const current = {login: 'reviewer', state: 'CHANGES_REQUESTED'};
  assert.deepEqual(await status({action: 'synchronize', labels: ['Needs Review'], reviews: [older, current]}), [remove]);
});

test('only a change request by another member waits on the author', async () => {
  const review = {event: 'pull_request_review', action: 'submitted'};
  assert.deepEqual(await status({...review, reviews: [{login: AUTHOR, state: 'CHANGES_REQUESTED'}]}), [add]);
  assert.deepEqual(await status({...review, reviews: [{login: 'visitor', state: 'CHANGES_REQUESTED', association: 'NONE'}]}), [add]);

  // A dismissed change request, or a comment after it, is no change request.
  const asked = {login: 'other', state: 'CHANGES_REQUESTED'};
  assert.deepEqual(await status({...review, reviews: [{login: 'other', state: 'DISMISSED'}]}), [add]);
  assert.deepEqual(await status({...review, labels: ['Needs Review'], reviews: [asked, {login: 'other', state: 'COMMENTED'}]}), [remove]);
});

test('draft and closed pull requests never keep Needs Review', async () => {
  assert.deepEqual(await status({action: 'synchronize', draft: true, labels: ['Needs Review']}), [remove]);
  assert.deepEqual(await status({event: 'pull_request_review', action: 'submitted', state: 'closed', labels: ['Needs Review']}),
    [remove]);
});

test('reviews of pull requests from forks are skipped', async () => {
  // Their token is read-only, so the script only logs.
  const review = {event: 'pull_request_review', action: 'submitted', fork: true, labels: ['Needs Review']};
  assert.deepEqual(await status({...review, reviews: [approved]}), []);

  // pull_request_target runs for forks have a token that can label.
  assert.deepEqual(await status({action: 'synchronize', fork: true, labels: ['Needs Review'], reviews: [approved]}), [remove]);
});

test('New contributor goes on a newcomer\'s first pull request', async () => {
  const label = [{action: 'add', labels: ['New contributor']}];
  assert.deepEqual(await run('newcomer', {action: 'opened'}, 'FIRST_TIME_CONTRIBUTOR'), label);
  assert.deepEqual(await run('newcomer', {action: 'opened'}, 'MEMBER'), []);
});

test('a newer event cancels an older status run of the same pull request', () => {
  for (const job of ['area', 'status']) {
    const {group, cancel} = jobConcurrency(job);
    assert.equal(cancel, 'true', job);
    assert.match(group ?? '', /github\.event\.pull_request\.number/, job);
  }

  // Skipped fork review runs must not cancel a run that can label.
  assert.match(jobConcurrency('status').group ?? '', /pull_request_review/);
});

// The state of one pull request under the rule.
const state = (pull: Pull) => {
  const {pr, reviews} = pullRequest(pull);
  return reviewState(pr, reviews);
};

test('reviewState names every state a pull request can be in', () => {
  const changes = {login: 'other', state: 'CHANGES_REQUESTED'};
  assert.equal(state({action: '', state: 'closed', reviews: [changes]}), State.CLOSED);
  assert.equal(state({action: '', draft: true, reviews: [approved]}), State.DRAFT);
  assert.equal(state({action: '', reviews: [approved]}), State.APPROVED);
  assert.equal(state({action: '', reviews: [changes]}), State.WAITING_ON_AUTHOR);
  assert.equal(state({action: ''}), State.NEEDS_REVIEW);
  assert.deepEqual(Object.values(State).sort(), ['approved', 'closed', 'draft', 'needs_review', 'waiting_on_author']);
});

test('reviewState moves between review states as reviews and pushes come in', () => {
  const changes = {login: 'other', state: 'CHANGES_REQUESTED'};
  const pushed = {...changes, commit: 'older-sha'};

  // Opened, changes requested, pushed, approved.
  assert.equal(state({action: ''}), State.NEEDS_REVIEW);
  assert.equal(state({action: '', reviews: [changes]}), State.WAITING_ON_AUTHOR);
  assert.equal(state({action: '', reviews: [pushed]}), State.NEEDS_REVIEW);
  assert.equal(state({action: '', reviews: [pushed, approved]}), State.APPROVED);

  // An approval, then changes requested by another member, then a push.
  assert.equal(state({action: '', reviews: [approved, changes]}), State.WAITING_ON_AUTHOR);
  assert.equal(state({action: '', reviews: [approved, pushed]}), State.NEEDS_REVIEW);

  // A dismissed approval or change request no longer counts.
  assert.equal(state({action: '', reviews: [{login: 'reviewer', state: 'DISMISSED'}]}), State.NEEDS_REVIEW);
  assert.equal(state({action: '', reviews: [changes, {login: 'other', state: 'DISMISSED'}]}), State.NEEDS_REVIEW);

  // Closing and drafting win over any review.
  assert.equal(state({action: '', state: 'closed', reviews: [approved]}), State.CLOSED);
  assert.equal(state({action: '', draft: true, reviews: [changes]}), State.DRAFT);
});

test('the sweep applies the rule to every open pull request', async () => {
  const sweep = (pulls: Pull[]) => runAll('sweep', pulls.map(pull => ({event: 'schedule', ...pull})));
  const changes = {login: 'other', state: 'CHANGES_REQUESTED'};
  assert.deepEqual(await sweep([
    // Approved under an older rule, still labelled.
    {action: '', number: 103, labels: ['Needs Review'], reviews: [approved]},
    // Waiting on its author.
    {action: '', number: 104, labels: ['Needs Review'], reviews: [changes]},
    // Missing its label, from a fork.
    {action: '', number: 105, fork: true},
    // Already right.
    {action: '', number: 106, labels: ['Needs Review']},
    {action: '', number: 107, draft: true},
    // Closed pull requests are not listed.
    {action: '', number: 108, state: 'closed', labels: ['Needs Review']},
  ]), [
    {...remove, number: 103},
    {...remove, number: 104},
    {...add, number: 105},
  ]);
});

test('the caller sweeps on schedule and workflow_dispatch', () => {
  const job = read(CALLER).match(/\n {2}pull-requests:\n((?: {4}.*\n| {6}.*\n)+)/);
  assert.ok(job, `${CALLER} has no job pull-requests`);
  for (const event of ['pull_request_target', 'pull_request_review', 'schedule', 'workflow_dispatch']) {
    assert.match(job[1], new RegExp(`"${event}"`), event);
  }
  assert.match(job[1], /pull-requests: write/);
  assert.match(read(PULL_REQUESTS), /\n {2}sweep:\n {4}if: github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\n/);
});

test('the status and sweep jobs load the rule from AnkiQuest-Dev, never pull request code', () => {
  const text = read(PULL_REQUESTS);
  for (const job of ['status', 'sweep']) {
    // The job runs up to the next job's header.
    const start = text.indexOf(`\n  ${job}:\n`);
    const next = text.slice(start + 1).search(/\n {2}[a-z-]+:\n/);
    const block = text.slice(start, next < 0 ? undefined : start + 1 + next);
    const checkout = block.match(/- uses: actions\/checkout@\S+.*\n {8}with:\n((?: {10}.*\n)+)/);
    assert.ok(checkout, `${job} has no checkout`);
    assert.match(checkout[1], /repository: AnkiQuest\/AnkiQuest-Dev\n/, job);
    assert.match(checkout[1], /ref: master\n/, job);
    assert.match(checkout[1], /path: ankiquest-dev\n/, job);
    assert.match(checkout[1], /persist-credentials: false\n/, job);
    assert.match(jobScript(PULL_REQUESTS, job), /require\('\.\/ankiquest-dev\/\.github\/scripts\/needs-review\.cjs'\)/, job);
  }
});

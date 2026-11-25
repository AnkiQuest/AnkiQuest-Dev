// "Needs Review" marks a pull request that waits on a reviewer. The jobs in
// pr-labels.yml load this file from a checkout of AnkiQuest-Dev's master;
// tests/labels.test.ts tests it.
//
// It reads the pull request and its reviews from the GitHub API and never
// checks out or runs pull request code.

const {Outcome, addLabel, removeLabel, transient} = require('./labels.cjs');

const LABEL = 'Needs Review';
const CONFLICTS = 'Has Conflicts';

// Reviews count from members only; GitHub ignores other approvals too. A
// comment keeps an earlier decision; a review dismissed, by hand or by
// branch protection on a push, has state DISMISSED.
const MEMBERS = ['OWNER', 'MEMBER', 'COLLABORATOR'];
const DECISIONS = ['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'];

// Where a pull request stands. Only NEEDS_REVIEW carries the label.
const State = Object.freeze({
  CLOSED: 'closed',
  DRAFT: 'draft',
  APPROVED: 'approved',
  WAITING_ON_AUTHOR: 'waiting_on_author',
  NEEDS_REVIEW: 'needs_review',
});

// Each other member's latest decision, with its position in the review list.
function latestDecisions(pr, reviews) {
  const latest = new Map();
  for (const [index, review] of reviews.entries()) {
    const login = review.user?.login;
    if (!login || login === pr.user.login) {
      continue;
    }
    if (!MEMBERS.includes(review.author_association) || !DECISIONS.includes(review.state)) {
      continue;
    }
    latest.set(login, {state: review.state, index, commit: review.commit_id});
  }
  return [...latest.values()];
}

// The state of a pull request from the pull request and its reviews, oldest
// first, as the GitHub API returns them.
function reviewState(pr, reviews) {
  if (pr.state === 'closed') {
    return State.CLOSED;
  }
  if (pr.draft) {
    return State.DRAFT;
  }

  // Approved: a standing approval with no change request after it.
  const decisions = latestDecisions(pr, reviews);
  const last = (state) => Math.max(-1, ...decisions.filter((d) => d.state === state).map((d) => d.index));
  const approval = last('APPROVED');
  if (approval >= 0 && last('CHANGES_REQUESTED') < approval) {
    return State.APPROVED;
  }

  // Changes requested on the current head wait on the author. A push makes
  // a new head, so the pull request needs review again.
  const asked = decisions.some((d) => d.state === 'CHANGES_REQUESTED' && d.commit === pr.head.sha);
  if (asked) {
    return State.WAITING_ON_AUTHOR;
  }
  return State.NEEDS_REVIEW;
}

// Sets the labels of one pull request to match its state, once. Returns
// the state and whether the labels were already right.
async function applyOnce({github, core, owner, repo, pr}) {
  const target = {github, core, owner, repo, issue_number: pr.number, labels: pr.labels};
  const reviews = await github.paginate(github.rest.pulls.listReviews, {owner, repo, pull_number: pr.number, per_page: 100});
  const state = reviewState(pr, reviews);
  core.info(`#${pr.number}: ${state}`);

  // Closed pull requests keep no workflow labels.
  const outcomes = [];
  if (state === State.CLOSED) {
    outcomes.push(await removeLabel({...target, name: LABEL}));
    outcomes.push(await removeLabel({...target, name: CONFLICTS}));
  } else if (state === State.NEEDS_REVIEW) {
    outcomes.push(await addLabel({...target, name: LABEL}));
  } else {
    outcomes.push(await removeLabel({...target, name: LABEL}));
  }
  return {state, settled: outcomes.every((outcome) => outcome === Outcome.UNCHANGED)};
}

// How often one run reads the pull request and applies its state.
const MAX_PASSES = 3;

// Sets one pull request's labels to match its state. `pr` is a pull request
// object from the API, read just before.
//
// Runs for the same pull request may overlap and one may write labels from
// an older read. So after a change the run reads the pull request again and
// repeats until a pass changes nothing: the last write on a pull request is
// always followed by a read of its current state.
//
// A read that GitHub keeps failing after the retries is reported, not
// thrown, so the job leaves no failed check; the result is then null.
async function syncLabels({github, core, owner, repo, pr}) {
  try {
    return await settle({github, core, owner, repo, pr});
  } catch (error) {
    if (!transient(error)) {
      throw error;
    }
    core.warning(`#${pr.number}: GitHub failed (${error.status}: ${error.message}); the next run or the sweep sets the labels`);
    return null;
  }
}

async function settle({github, core, owner, repo, pr}) {
  let current = pr;
  for (let pass = 1; ; pass++) {
    const {state, settled} = await applyOnce({github, core, owner, repo, pr: current});
    if (settled) {
      return state;
    }
    if (pass === MAX_PASSES) {
      core.warning(`#${pr.number}: labels not settled after ${MAX_PASSES} passes; the next run or the sweep sets them`);
      return state;
    }
    ({data: current} = await github.rest.pulls.get({owner, repo, pull_number: pr.number}));
  }
}

module.exports = {LABEL, MAX_PASSES, State, reviewState, syncLabels};

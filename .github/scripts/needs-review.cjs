// "Needs Review" marks a pull request that waits on a reviewer. The jobs in
// pr-labels.yml load this file from a checkout of AnkiQuest-Dev's master;
// tests/labels.test.ts tests it.
//
// It reads the pull request and its reviews from the GitHub API and never
// checks out or runs pull request code.

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

// Reads one pull request's reviews and sets its labels to match its state.
// `pr` is a pull request object from the API, read just before.
async function syncLabels({github, core, owner, repo, pr}) {
  const issue_number = pr.number;

  // Label names are case-insensitive on GitHub.
  const has = (name) => pr.labels.some((label) => label.name.toLowerCase() === name.toLowerCase());

  async function add(name) {
    if (has(name)) {
      return;
    }
    core.info(`#${issue_number}: adding "${name}"`);
    await github.rest.issues.addLabels({owner, repo, issue_number, labels: [name]});
  }

  async function remove(name) {
    if (!has(name)) {
      return;
    }
    core.info(`#${issue_number}: removing "${name}"`);
    try {
      await github.rest.issues.removeLabel({owner, repo, issue_number, name});
    } catch (error) {
      if (error.status !== 404) {
        throw error;
      }
    }
  }

  const reviews = await github.paginate(github.rest.pulls.listReviews, {owner, repo, pull_number: pr.number, per_page: 100});
  const state = reviewState(pr, reviews);
  core.info(`#${issue_number}: ${state}`);

  // Closed pull requests keep no workflow labels.
  if (state === State.CLOSED) {
    await remove(LABEL);
    await remove(CONFLICTS);
    return state;
  }
  if (state === State.NEEDS_REVIEW) {
    await add(LABEL);
    return state;
  }
  await remove(LABEL);
  return state;
}

module.exports = {LABEL, State, reviewState, syncLabels};

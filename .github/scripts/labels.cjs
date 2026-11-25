// Adds and removes one label on an issue or pull request, for the label
// jobs in pr-labels.yml, issue-labels.yml and the conflict-scan action.
// tests/labels.test.ts tests it.
//
// Label jobs run concurrently, without a concurrency group: GitHub cancels
// queued runs of a group, and a cancelled run stays on the head commit as a
// failed check. So every call here is idempotent, and a call that GitHub
// refuses or fails after its retries is reported, not thrown: the caller
// reads the current labels again, and the next run or the sweep corrects
// what is still wrong.
//
// actions/github-script retries 5xx and 429 responses itself (its `retries`
// input); this file retries secondary rate limits, which come as 403.

const Status = Object.freeze({
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  UNPROCESSABLE: 422,
  SERVER_ERROR: 500,
});

// What one add or remove did.
const Outcome = Object.freeze({
  // The label was already as wanted; no request was made.
  UNCHANGED: 'unchanged',
  // GitHub accepted the change.
  CHANGED: 'changed',
  // GitHub refused it because the label was not as read: already removed
  // (404) or already there (422).
  STALE: 'stale',
  // GitHub kept failing (5xx or rate limit) after the retries.
  FAILED: 'failed',
});

// Secondary rate limits: how often to wait, and how long when GitHub gives
// no Retry-After.
const RATE_LIMIT_ATTEMPTS = 3;
const RATE_LIMIT_WAIT_SECONDS = 60;

const sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

function rateLimited(error) {
  return error.status === Status.FORBIDDEN && /secondary rate limit/i.test(error.message ?? '');
}

// A failure that a later run can be expected not to hit.
function transient(error) {
  return rateLimited(error) || error.status >= Status.SERVER_ERROR;
}

// Calls `request`, waiting out secondary rate limits.
async function withRateLimit(core, request) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await request();
    } catch (error) {
      if (!rateLimited(error) || attempt === RATE_LIMIT_ATTEMPTS) {
        throw error;
      }
      const wait = Number(error.response?.headers?.['retry-after']) || RATE_LIMIT_WAIT_SECONDS;
      core.info(`Secondary rate limit, retrying in ${wait} s`);
      await sleep(wait);
    }
  }
}

// Runs one label request and names its outcome. `refused` is the status
// that means the label was already as wanted.
async function change(core, what, refused, request) {
  try {
    await withRateLimit(core, request);
    return Outcome.CHANGED;
  } catch (error) {
    if (error.status === refused) {
      core.info(`${what}: already done (${error.status})`);
      return Outcome.STALE;
    }
    if (transient(error)) {
      core.warning(`${what}: failed (${error.status}: ${error.message})`);
      return Outcome.FAILED;
    }
    throw error;
  }
}

// Label names are case-insensitive on GitHub. `labels` is the issue's
// labels as the API returned them.
function hasLabel(labels, name) {
  return labels.some((label) => label.name.toLowerCase() === name.toLowerCase());
}

async function addLabel({github, core, owner, repo, issue_number, labels, name}) {
  if (hasLabel(labels, name)) {
    return Outcome.UNCHANGED;
  }
  const what = `#${issue_number}: adding "${name}"`;
  core.info(what);
  return change(core, what, Status.UNPROCESSABLE, () =>
    github.rest.issues.addLabels({owner, repo, issue_number, labels: [name]}));
}

async function removeLabel({github, core, owner, repo, issue_number, labels, name}) {
  if (!hasLabel(labels, name)) {
    return Outcome.UNCHANGED;
  }
  const what = `#${issue_number}: removing "${name}"`;
  core.info(what);
  return change(core, what, Status.NOT_FOUND, () =>
    github.rest.issues.removeLabel({owner, repo, issue_number, name}));
}

module.exports = {Outcome, addLabel, removeLabel, hasLabel, transient, withRateLimit};

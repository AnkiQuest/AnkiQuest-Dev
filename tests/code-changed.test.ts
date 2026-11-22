// The glob rules of the code-changed action (.github/actions/code-changed):
// which paths its default docs globs and extra globs count as documentation.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const action = path.join(root, '.github', 'actions', 'code-changed');
const MATCH = path.join(action, 'match.sh');

// The `docs` input's default, the list callers get without setting it.
function defaultDocs(): string {
  const text = fs.readFileSync(path.join(action, 'action.yml'), 'utf8');
  const block = text.match(/\n {2}docs:\n(?: {4}.*\n)*? {4}default: \|\n((?: {6}.*\n)+)/);
  assert.ok(block, 'action.yml has no docs default');
  return block[1].replace(/^ {6}/gm, '');
}

// Each path's kind, docs or code, under the given globs.
function sort(globs: string, paths: string[]): Record<string, string> {
  const out = execFileSync('bash', [MATCH], {input: paths.join('\n') + '\n', env: {...process.env, GLOBS: globs}, encoding: 'utf8'});
  return Object.fromEntries(out.trimEnd().split('\n').map(line => line.split('\t').reverse()));
}

function check(globs: string, docs: string[], code: string[]) {
  const kinds = sort(globs, [...docs, ...code]);
  for (const file of docs) {
    assert.equal(kinds[file], 'docs', file);
  }
  for (const file of code) {
    assert.equal(kinds[file], 'code', file);
  }
}

test('the default globs are the policy\'s docs-only list', () => {
  assert.deepEqual(defaultDocs().trim().split('\n'), [
    '**/*.md', 'LICENSE*', 'LICENSES/**', 'docs/**', '.github/ISSUE_TEMPLATE/**', '.github/pull_request_template.md',
  ]);
});

test('the default globs match documentation at any depth and nothing else', () => {
  check(defaultDocs(), [
    'README.md', 'AGENTS.md', 'CLAUDE.md', 'a/README.md', 'a/b/c/notes.md', '.github/copilot.md',
    'LICENSE', 'LICENSE-MIT', 'LICENSES/AGPL-3.0.txt', 'LICENSES/a/b.txt',
    'docs/guide.txt', 'docs/graphics/banner.png', 'docs/a/b/c.toml',
    '.github/ISSUE_TEMPLATE/bug.yml', '.github/pull_request_template.md',
    'a+b (1).md', 'with space.md',
  ], [
    'flake.nix', 'src/main.rs', '.github/workflows/ci.yml', '.github/actions/code-changed/action.yml',
    'README.mdx', 'README.md.orig', 'a.md/main.rs', 'readme', 'docs', 'mydocs/a.md.txt', 'a/docs/x.png',
    'tools/banner/fonts/LICENSE-Roboto.txt', '.github/ISSUE_TEMPLATE',
    '.github/workflows/pull_request_template.md.yml',
  ]);
});

test('* and ? stay within a directory, ** spans directories', () => {
  check('static/**/*.png\nv?.txt\n*.txt\nweb/**', [
    'static/a.png', 'static/a/b/c.png', 'v1.txt', 'notes.txt', 'web/x', 'web/a/b/c.ts',
  ], [
    'static/a.jpg', 'static.png', 'a/static/a.png', 'v/.txt', 'a/notes.txt', 'web', 'webx/a',
  ]);
});

test('regular expression characters in a glob are literal', () => {
  check('file[1].txt\na+b.md5\n$x(y)|z{1}^\\q', ['file[1].txt', 'a+b.md5', '$x(y)|z{1}^\\q'], ['file1.txt', 'aab.md5', 'x']);
});

test('blank lines, comments and surrounding space in the globs are ignored', () => {
  check('\n  # a comment\n   *.md  \n\n', ['a.md'], ['# a comment', 'a.txt']);
});

test('without globs every path is code', () => {
  check('', [], ['README.md', 'docs/a.txt']);
});

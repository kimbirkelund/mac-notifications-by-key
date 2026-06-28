import { Given, When, Then } from '@cucumber/cucumber'
import assert from 'node:assert/strict'

// Split a `nbk ...` command string into argv, respecting double quotes, and drop
// the leading "nbk" (the binary path is injected by the world).
function tokenize(command) {
  const matches = command.match(/(?:[^\s"]+|"[^"]*")+/g) ?? []
  const tokens = matches.map((t) => t.replace(/^"|"$/g, '').replace(/\\"/g, '"'))
  if (tokens[0] === 'nbk') tokens.shift()
  return tokens
}

Given('a notification is delivered with title {string}', async function (title) {
  await this.deliver(title)
})

// Keyword-agnostic in cucumber: this also matches `And I run "..."` used as a
// precondition in a Given block.
When('I run {string}', async function (command) {
  await this.runNbk(tokenize(command))
})

Then('the command succeeds', function () {
  assert.equal(
    this.lastResult.code,
    0,
    `expected exit 0, got ${this.lastResult.code}: ${this.lastResult.stderr}`
  )
})

Then('the command fails', function () {
  assert.notEqual(this.lastResult.code, 0, 'expected a non-zero exit')
})

Then('the JSON output contains a notification with title {string}', function (title) {
  const items = JSON.parse(this.lastResult.stdout)
  assert.ok(
    Array.isArray(items) && items.some((n) => n.title === title),
    `expected a notification titled "${title}" in: ${this.lastResult.stdout}`
  )
})

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

Given('no notifications are presented', async function () {
  await this.clearTestNotifications()
})

// RNA-9: no API revokes Accessibility trust, so a human operator stands in. Prompt
// them, then confirm the substitute precondition actually holds before proceeding.
Given('the operator has revoked Accessibility trust for the test runner', async function () {
  await this.promptOperator(
    `Revoke Accessibility trust for ${this.runnerProcessHint}. Toggle it off (or remove it), ` +
      'then return here.'
  )
  assert.equal(
    await this.isTrusted(),
    false,
    'expected Accessibility trust to be revoked, but nbk still reports trusted'
  )
})

// Schedule (do not await) a delivery so it fires while a later `list --wait`
// step is already polling. Proves --wait catches post-invocation deliveries.
When('a notification with title {string} is delivered after {int} seconds', function (title, secs) {
  this.scheduleDelivery(title, secs * 1000)
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

Then('the JSON output is an empty array', function () {
  let parsed
  try {
    parsed = JSON.parse(this.lastResult.stdout)
  } catch (err) {
    assert.fail(`stdout is not valid JSON: ${err.message}; got: ${this.lastResult.stdout}`)
  }
  assert.ok(Array.isArray(parsed), `expected a JSON array, got: ${this.lastResult.stdout}`)
  assert.equal(parsed.length, 0, `expected an empty array, got: ${this.lastResult.stdout}`)
})

// Asserts against the captured `list --wait` output directly (no re-poll), so a
// broken --wait can't be masked by a later list.
Then('the JSON output includes a notification with title {string}', function (title) {
  let parsed
  try {
    parsed = JSON.parse(this.lastResult.stdout)
  } catch (err) {
    assert.fail(`stdout is not valid JSON: ${err.message}; got: ${this.lastResult.stdout}`)
  }
  assert.ok(Array.isArray(parsed), `expected a JSON array, got: ${this.lastResult.stdout}`)
  assert.ok(
    parsed.some((n) => n.title === title),
    `expected a notification titled "${title}"; got: ${this.lastResult.stdout}`
  )
})

// Asserts against the captured `list` output directly (RNA-4: dismissed → absent).
Then('the JSON output does not include a notification with title {string}', function (title) {
  let parsed
  try {
    parsed = JSON.parse(this.lastResult.stdout)
  } catch (err) {
    assert.fail(`stdout is not valid JSON: ${err.message}; got: ${this.lastResult.stdout}`)
  }
  assert.ok(Array.isArray(parsed), `expected a JSON array, got: ${this.lastResult.stdout}`)
  assert.ok(
    !parsed.some((n) => n.title === title),
    `expected no notification titled "${title}"; got: ${this.lastResult.stdout}`
  )
})

Then('the JSON output contains a notification with title {string}', async function (title) {
  // Poll rather than trust the single captured `list`: a banner can take a moment
  // to render, and `--wait` can return early on an unrelated notification.
  const found = await this.waitForTitle(title)
  assert.ok(
    found,
    `expected a notification titled "${title}"; last list: ${this.lastResult?.stdout}`
  )
})

// RNA-7: the error must name the offending index as unavailable.
Then('the error output mentions an out-of-range index', function () {
  const err = this.lastResult.stderr.toLowerCase()
  assert.ok(
    /index/.test(err) && /(out of range|no notification)/.test(err),
    `expected an out-of-range index error; got: ${this.lastResult.stderr}`
  )
})

// RNA-8: the error must list the actions the notification does expose.
Then('the error output lists the available actions', function () {
  const err = this.lastResult.stderr
  assert.ok(
    /does not expose/i.test(err) && /available:/i.test(err),
    `expected the error to list available actions; got: ${err}`
  )
})

// RNA-10: doctor reports trust, the Notification Center process, and macOS version.
Then(
  'the doctor output reports trust, the Notification Center process, and the macOS version',
  function () {
    const out = this.lastResult.stdout
    assert.ok(/accessibility_trust:/i.test(out), `missing trust line; got: ${out}`)
    assert.ok(/notification_center_pid:/i.test(out), `missing NC process line; got: ${out}`)
    assert.ok(/macos:/i.test(out), `missing macOS version line; got: ${out}`)
  }
)

// RNA-9: the error must explain how to grant Accessibility permission.
Then('the error output explains how to grant Accessibility permission', function () {
  const err = this.lastResult.stderr.toLowerCase()
  assert.ok(
    /accessibility/.test(err) && /system settings/.test(err),
    `expected stderr to explain granting Accessibility permission; got: ${this.lastResult.stderr}`
  )
})

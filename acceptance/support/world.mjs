import { setWorldConstructor, World } from '@cucumber/cucumber'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'

const run = promisify(execFile)

// The compiled CLI under test. build.ps1 sets NBK_BIN; default to the debug build.
const NBK_BIN = process.env.NBK_BIN ?? '.build/debug/nbk'

/**
 * Black-box world: delivers real notifications and invokes the nbk binary,
 * capturing exit code / stdout / stderr for assertions.
 */
class NbkWorld extends World {
  lastResult = null

  async deliver(title, body = 'acceptance body') {
    await run('osascript', ['-e', `display notification "${body}" with title "${title}"`])
  }

  async runNbk(argv) {
    try {
      const { stdout, stderr } = await run(NBK_BIN, argv, { maxBuffer: 16 * 1024 * 1024 })
      this.lastResult = { code: 0, stdout, stderr }
    } catch (err) {
      this.lastResult = {
        code: typeof err.code === 'number' ? err.code : 1,
        stdout: err.stdout ?? '',
        stderr: err.stderr ?? ''
      }
    }
    return this.lastResult
  }
}

setWorldConstructor(NbkWorld)

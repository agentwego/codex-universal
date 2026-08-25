from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent
PATCH_SCRIPT = REPO_ROOT / "opencli-cdp-patch.py"


class OpenCliCdpPatchTests(unittest.TestCase):
    def _package_fixture(self, root: Path) -> Path:
        package_root = root / "opencli"
        dist = package_root / "dist" / "src"
        dist.mkdir(parents=True)

        (dist / "runtime.js").write_text(
            """export function getBrowserFactory(site) {
    if (site && isElectronApp(site))
        return CDPBridge;
    return BrowserBridge;
}
""",
            encoding="utf-8",
        )
        (dist / "execution.js").write_text(
            """import { probeCDP, resolveElectronEndpoint } from './launcher.js';

            const electron = isElectronApp(cmd.site);
            let cdpEndpoint;
            if (electron) {
                // Electron apps: respect manual endpoint override, then try auto-detect
                const manualEndpoint = process.env.OPENCLI_CDP_ENDPOINT;
                if (manualEndpoint) {
                    const port = Number(new URL(manualEndpoint).port);
                    if (!await probeCDP(port)) {
                        throw new CommandExecutionError(`CDP not reachable at ${manualEndpoint}`, 'Check that the app is running with --remote-debugging-port and the endpoint is correct.');
                    }
                    cdpEndpoint = manualEndpoint;
                }
                else {
                    cdpEndpoint = await resolveElectronEndpoint(cmd.site);
                }
            }
            const BrowserFactory = getBrowserFactory(cmd.site);
""",
            encoding="utf-8",
        )
        (dist / "cli.js").write_text(
            """async function getBrowserPage(session, targetPage, profileSelection, opts = {}) {
    const { BrowserBridge } = await import('./browser/index.js');
    const bridge = new BrowserBridge();
    // Internal GC timeout for browser sessions. Not the per-command runtime timeout.
    const envTimeout = process.env.OPENCLI_BROWSER_IDLE_TIMEOUT;
    const idleTimeout = envTimeout ? parseInt(envTimeout, 10) : undefined;
    const page = await bridge.connect({
        timeout: DEFAULT_BROWSER_CONNECT_TIMEOUT,
        session,
        surface: 'browser',
    });
    const resolvedTargetPage = targetPage;
    if (resolvedTargetPage) {
        if (!page.setActivePage) {
            throw new Error('This browser session does not support explicit tab targeting');
        }
        page.setActivePage(resolvedTargetPage);
    }
    return page;
}

            catch (err) {
                process.exitCode = EXIT_CODES.GENERIC_ERROR;
            }
        };
    }
    function browserSessionCommandAction(fn) {}

    program
        .command('doctor')
        .description('Diagnose opencli browser bridge connectivity')
        .option('-v, --verbose', 'Debug output')
        .action(async (opts) => {
        applyVerbose(opts);
        const { runBrowserDoctor, renderBrowserDoctorReport } = await import('./doctor.js');
        const report = await runBrowserDoctor({ cliVersion: PKG_VERSION });
        console.log(renderBrowserDoctorReport(report));
    });
""",
            encoding="utf-8",
        )
        return package_root

    def test_patch_adds_direct_cdp_doctor_and_keeps_bridge_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = self._package_fixture(Path(tmp))
            subprocess.run(
                [sys.executable, str(PATCH_SCRIPT), str(package_root)],
                check=True,
                capture_output=True,
                text=True,
            )

            cli = (package_root / "dist" / "src" / "cli.js").read_text(
                encoding="utf-8"
            )
            self.assertIn("Direct CDP", cli)
            self.assertIn("Browser.getVersion", cli)
            self.assertIn("await bridge.close()", cli)
            self.assertIn("runBrowserDoctor", cli)
            self.assertIn("renderBrowserDoctorReport", cli)


if __name__ == "__main__":
    unittest.main()

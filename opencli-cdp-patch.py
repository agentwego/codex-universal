#!/usr/bin/env python3
"""Patch OpenCLI 1.8.7 so OPENCLI_CDP_ENDPOINT applies to web adapters and browser primitives.

Remove this patch once https://github.com/jackwener/OpenCLI/issues/867 is fixed
in a released npm package. Exact replacements deliberately fail closed when
upstream code changes, so image builds cannot silently ship a half-applied fix.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_exact(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "package_root",
        type=Path,
        help="Installed @jackwener/opencli package root",
    )
    args = parser.parse_args()
    dist = args.package_root / "dist" / "src"

    replace_exact(
        dist / "runtime.js",
        """export function getBrowserFactory(site) {
    if (site && isElectronApp(site))
        return CDPBridge;
    return BrowserBridge;
}""",
        """export function getBrowserFactory(site) {
    if (process.env.OPENCLI_CDP_ENDPOINT?.trim())
        return CDPBridge;
    if (site && isElectronApp(site))
        return CDPBridge;
    return BrowserBridge;
}""",
    )

    replace_exact(
        dist / "execution.js",
        """import { probeCDP, resolveElectronEndpoint } from './launcher.js';""",
        """import { resolveElectronEndpoint } from './launcher.js';""",
    )
    replace_exact(
        dist / "execution.js",
        """            const electron = isElectronApp(cmd.site);
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
            const BrowserFactory = getBrowserFactory(cmd.site);""",
        """            const electron = isElectronApp(cmd.site);
            const manualEndpoint = process.env.OPENCLI_CDP_ENDPOINT?.trim() || undefined;
            let cdpEndpoint;
            if (manualEndpoint) {
                // Manual CDP is a full endpoint and may be remote or reverse-proxied.
                // CDPBridge validates it by fetching /json instead of probing localhost.
                cdpEndpoint = manualEndpoint;
            }
            else if (electron) {
                cdpEndpoint = await resolveElectronEndpoint(cmd.site);
            }
            const BrowserFactory = getBrowserFactory(cmd.site);""",
    )

    replace_exact(
        dist / "cli.js",
        """async function getBrowserPage(session, targetPage, profileSelection, opts = {}) {
    const { BrowserBridge } = await import('./browser/index.js');
    const bridge = new BrowserBridge();
    // Internal GC timeout for browser sessions. Not the per-command runtime timeout.
    const envTimeout = process.env.OPENCLI_BROWSER_IDLE_TIMEOUT;
    const idleTimeout = envTimeout ? parseInt(envTimeout, 10) : undefined;
    const page = await bridge.connect({
        timeout: DEFAULT_BROWSER_CONNECT_TIMEOUT,
        session,
        surface: 'browser',""",
        """async function getBrowserPage(session, targetPage, profileSelection, opts = {}) {
    const { BrowserBridge, CDPBridge } = await import('./browser/index.js');
    const cdpEndpoint = process.env.OPENCLI_CDP_ENDPOINT?.trim() || undefined;
    const bridge = cdpEndpoint ? new CDPBridge() : new BrowserBridge();
    // Internal GC timeout for browser sessions. Not the per-command runtime timeout.
    const envTimeout = process.env.OPENCLI_BROWSER_IDLE_TIMEOUT;
    const idleTimeout = envTimeout ? parseInt(envTimeout, 10) : undefined;
    const page = await bridge.connect({
        timeout: DEFAULT_BROWSER_CONNECT_TIMEOUT,
        session,
        cdpEndpoint,
        surface: 'browser',""",
    )
    replace_exact(
        dist / "cli.js",
        """    if (resolvedTargetPage) {
        if (!page.setActivePage) {
            throw new Error('This browser session does not support explicit tab targeting');
        }
        page.setActivePage(resolvedTargetPage);
    }
    return page;
}""",
        """    if (resolvedTargetPage) {
        if (!page.setActivePage) {
            throw new Error('This browser session does not support explicit tab targeting');
        }
        page.setActivePage(resolvedTargetPage);
    }
    if (cdpEndpoint) {
        // CDPBridge pages do not carry BrowserBridge's routing metadata, but
        // browser commands use it for tab state, sitemap hints, and output.
        page.session = session;
        page.preferredContextId = profileSelection?.contextId;
        page.__opencliCloseTransport = () => bridge.close();
    }
    return page;
}""",
    )
    replace_exact(
        dist / "cli.js",
        """                process.exitCode = EXIT_CODES.GENERIC_ERROR;
            }
        };
    }
    function browserSessionCommandAction(fn) {""",
        """                process.exitCode = EXIT_CODES.GENERIC_ERROR;
            }
            finally {
                await page?.__opencliCloseTransport?.().catch(() => { });
            }
        };
    }
    function browserSessionCommandAction(fn) {""",
    )

    print(f"patched OpenCLI CDP routing under {args.package_root}")


if __name__ == "__main__":
    main()

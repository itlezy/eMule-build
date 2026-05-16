"""Release package orchestration."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import struct
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from .build import app_binary_path, app_property_overrides, ensure_app_dependency_artifacts, verify_app_control_flow_guard
from .build_state import BuildSession
from .config import ReleasePackageOptions, WorkspaceOptions
from .git import git_output, repo_branch, repo_head, repo_status_lines
from .layout import AppVariant, WorkspaceLayout
from .msbuild import env_override, invoke_msbuild_project

PE_MACHINES = {"x64": 0x8664, "ARM64": 0xAA64}


def create_release_package(
    layout: WorkspaceLayout,
    workspace_options: WorkspaceOptions,
    package_options: ReleasePackageOptions,
) -> None:
    """Builds the main app and creates a release ZIP plus manifest."""

    if workspace_options.configuration != "Release":
        raise RuntimeError("package release requires --config Release.")
    if not re.fullmatch(r"\d+\.\d+\.\d+", package_options.release_version):
        raise RuntimeError(f"Release version must use MAJOR.MINOR.PATCH format: {package_options.release_version}")

    ensure_canonical_app_anchor(layout)
    app_variant = layout.get_app_variant("main")
    app_root = app_variant.path
    _assert_release_source_branch(app_variant)
    _assert_clean_release_inputs(layout, app_root)
    _assert_package_version_matches_app(app_root, package_options.release_version)

    session = BuildSession(
        layout=layout,
        options=workspace_options,
        command_name="package release",
        clean=package_options.clean,
        stamp=time.strftime("%Y%m%d-%H%M%S"),
    )
    try:
        _build_package_app(session, app_root, package_options.clean)
        _build_language_resources(session, app_root, package_options.clean)
    finally:
        session.write_recap()

    build_output_root = app_root / "srchybrid" / workspace_options.platform / workspace_options.configuration
    exe_path = build_output_root / "emule.exe"
    expected_language_dlls = _expected_language_dlls(layout.tooling_repo_root)
    lang_path = _package_language_path(app_root, workspace_options.platform, expected_language_dlls)
    webserver_path = _package_webserver_path(app_root, build_output_root)
    for required_path in (exe_path, lang_path, webserver_path):
        if not required_path.exists():
            raise RuntimeError(f"Cannot package missing release runtime path: {required_path}")
    _assert_pe_machine(exe_path, workspace_options.platform)

    asset_arch = "arm64" if workspace_options.platform == "ARM64" else "x64"
    release_root = layout.workspace_root / "state" / "release" / f"emule-bb-v{package_options.release_version}"
    staging_root = release_root / "staging" / asset_arch
    package_root = staging_root / "eMule"
    zip_path = release_root / f"eMule-broadband-{package_options.release_version}-{asset_arch}.zip"
    manifest_path = release_root / f"eMule-broadband-{package_options.release_version}-{asset_arch}.manifest.json"
    for path_to_check in (staging_root, package_root, zip_path, manifest_path):
        _assert_path_under_root(path_to_check, release_root, "release package path")

    if staging_root.exists():
        shutil.rmtree(staging_root)
    package_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(exe_path, package_root / "emule.exe")
    _copy_directory_contents(lang_path, package_root / "lang")
    _copy_directory_contents(webserver_path, package_root / "webserver")
    _write_package_readme(package_root, package_options.release_version, workspace_options.platform)
    _write_package_release_notes(package_root, package_options.release_version)
    _write_package_license_notice(package_root)
    _write_package_third_party_notices(package_root)
    _write_package_gpl_text(layout, package_root)
    _copy_package_file(
        layout.tooling_repo_root / "docs" / "rest" / "REST-API-CONTRACT.md",
        package_root,
        Path("docs/REST-API-CONTRACT.md"),
    )
    _copy_package_file(
        layout.tooling_repo_root / "docs" / "rest" / "REST-API-OPENAPI.yaml",
        package_root,
        Path("docs/REST-API-OPENAPI.yaml"),
    )
    _copy_package_file(
        layout.tooling_repo_root / "docs" / "rest" / "REST-API-PARITY-INVENTORY.md",
        package_root,
        Path("docs/REST-API-PARITY-INVENTORY.md"),
    )

    if zip_path.exists():
        zip_path.unlink()
    release_root.mkdir(parents=True, exist_ok=True)
    _write_zip(staging_root, package_root, zip_path)
    _assert_release_package_contents(zip_path, expected_language_dlls, workspace_options.platform)

    zip_hash = _sha256(zip_path)
    exe_hash = _sha256(exe_path)
    package_file_hashes = _zip_entry_hashes(zip_path)
    manifest = _build_release_manifest(
        layout=layout,
        workspace_options=workspace_options,
        package_options=package_options,
        app_variant=app_variant,
        app_root=app_root,
        zip_path=zip_path,
        release_root=release_root,
        zip_hash=zip_hash,
        exe_hash=exe_hash,
        expected_language_dlls=expected_language_dlls,
        package_file_hashes=package_file_hashes,
    )
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Release package: {zip_path}")
    print(f"Release manifest: {manifest_path}")
    print(f"SHA256: {zip_hash}")


def _build_release_manifest(
    *,
    layout: WorkspaceLayout,
    workspace_options: WorkspaceOptions,
    package_options: ReleasePackageOptions,
    app_variant: AppVariant,
    app_root: Path,
    zip_path: Path,
    release_root: Path,
    zip_hash: str,
    exe_hash: str,
    expected_language_dlls: tuple[str, ...],
    package_file_hashes: dict[str, str],
) -> dict[str, object]:
    """Builds the provenance manifest written next to one release asset."""

    return {
        "product": "eMule broadband edition",
        "compactName": "eMule BB",
        "version": package_options.release_version,
        "tag": f"emule-bb-v{package_options.release_version}",
        "configuration": workspace_options.configuration,
        "platform": workspace_options.platform,
        "asset": zip_path.name,
        "assetPath": zip_path.relative_to(release_root).as_posix(),
        "sha256": zip_hash,
        "emuleExeSha256": exe_hash,
        "languageDllCount": len(expected_language_dlls),
        "languageDlls": list(expected_language_dlls),
        "packageFileSha256": package_file_hashes,
        "appVariant": app_variant.name,
        "appBranch": repo_branch(app_root),
        "appCommit": repo_head(app_root),
        "buildBranch": repo_branch(layout.build_repo_root),
        "buildCommit": repo_head(layout.build_repo_root),
        "buildTestsBranch": repo_branch(layout.tests_repo_root),
        "buildTestsCommit": repo_head(layout.tests_repo_root),
        "toolingBranch": repo_branch(layout.tooling_repo_root),
        "toolingCommit": repo_head(layout.tooling_repo_root),
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "includedPaths": [
            "eMule/emule.exe",
            "eMule/lang",
            "eMule/webserver",
            "eMule/README.md",
            "eMule/RELEASE-NOTES.md",
            "eMule/LICENSE-NOTICE.txt",
            "eMule/GPL-2.0-or-later.txt",
            "eMule/THIRD-PARTY-NOTICES.txt",
            "eMule/docs/REST-API-CONTRACT.md",
            "eMule/docs/REST-API-OPENAPI.yaml",
            "eMule/docs/REST-API-PARITY-INVENTORY.md",
        ],
    }


def _assert_release_source_branch(app_variant: AppVariant) -> None:
    """Requires release packages to come from the configured source branch."""

    current_branch = repo_branch(app_variant.path)
    if current_branch != app_variant.branch:
        raise RuntimeError(
            "package release requires app variant "
            f"'{app_variant.name}' at {app_variant.path} to be on branch "
            f"'{app_variant.branch}', not '{current_branch}'."
        )


def _assert_clean_release_inputs(layout: WorkspaceLayout, app_root: Path) -> None:
    """Rejects dirty inputs whose exact commits are recorded in the manifest."""

    repos = (
        ("app source", app_root),
        ("build orchestration", layout.build_repo_root),
        ("build tests", layout.tests_repo_root),
        ("tooling docs", layout.tooling_repo_root),
    )
    dirty_inputs: list[str] = []
    for label, repo_path in repos:
        changes = [line for line in repo_status_lines(repo_path) if not line.startswith("## ")]
        if changes:
            sample = "\n    ".join(changes[:20])
            dirty_inputs.append(f"- {label}: {repo_path}\n    {sample}")
    if dirty_inputs:
        raise RuntimeError(
            "package release requires clean provenance inputs before writing assets:\n"
            + "\n".join(dirty_inputs)
        )


def ensure_canonical_app_anchor(layout: WorkspaceLayout) -> None:
    """Ensures the canonical app repo is clean and detached at origin/main."""

    canonical_repo_path = layout.seed_repo_path
    if not canonical_repo_path.is_dir():
        raise RuntimeError(f"Canonical app repo is missing: {canonical_repo_path}")
    status_lines = repo_status_lines(canonical_repo_path)
    if len(status_lines) > 1:
        raise RuntimeError(f"Canonical app repo has local changes and cannot be re-anchored automatically: {canonical_repo_path}")
    expected_revision = f"refs/remotes/origin/{layout.seed_repo_branch}"
    expected_head = git_output(canonical_repo_path, "rev-parse", expected_revision).strip()
    current_branch = repo_branch(canonical_repo_path)
    current_head = git_output(canonical_repo_path, "rev-parse", "HEAD").strip()
    if current_branch == "HEAD" and current_head == expected_head:
        return
    print(f"Reanchoring canonical app repo to detached origin/{layout.seed_repo_branch} at {expected_head}")
    git_output(canonical_repo_path, "checkout", "--detach", expected_revision)


def _build_package_app(session: BuildSession, app_root: Path, clean: bool) -> None:
    target = "Rebuild" if clean else "Build"
    ensure_app_dependency_artifacts(session.layout, session.options, clean=clean)
    extra_properties = [*app_property_overrides(session.layout, session.options.platform)]
    override = env_override(session.layout.toolset_override_variable)
    if override:
        extra_properties.append(f"/p:PlatformToolset={override}")
    invoke_msbuild_project(
        session,
        project_path=app_root / "srchybrid" / "emule.vcxproj",
        extra_properties=extra_properties,
        target=target,
        step_name="APP main package binary",
    )
    verify_app_control_flow_guard(
        session,
        binary_path=app_binary_path(app_root, session.options.configuration, session.options.platform),
        step_name="APP main package binary CFG",
    )


def _build_language_resources(session: BuildSession, app_root: Path, clean: bool) -> None:
    language_solution = app_root / "srchybrid" / "lang" / "lang.sln"
    if not language_solution.is_file():
        raise RuntimeError(f"Cannot build missing language solution: {language_solution}")
    target = "Rebuild" if clean else "Build"
    invoke_msbuild_project(
        session,
        project_path=language_solution,
        configuration="Dynamic",
        platform=session.options.platform,
        extra_properties=(_default_platform_toolset_property(session.layout),),
        target=target,
        step_name="APP main language resources",
    )


def _default_platform_toolset_property(layout: WorkspaceLayout) -> str:
    override = env_override(layout.toolset_override_variable)
    return f"/p:PlatformToolset={override}" if override else "/p:PlatformToolset=v143"


def _expected_language_dlls(tooling_repo_root: Path) -> tuple[str, ...]:
    """Returns the release language DLL names from the stock language manifest."""

    manifest_path = tooling_repo_root / "helpers" / "rc-release-languages.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"Cannot package without release language manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    languages = manifest.get("languages")
    if not isinstance(languages, list) or not languages:
        raise RuntimeError(f"Release language manifest has no languages: {manifest_path}")
    dlls: list[str] = []
    for entry in languages:
        rc_name = entry.get("rc") if isinstance(entry, dict) else None
        if not isinstance(rc_name, str) or not rc_name.endswith(".rc"):
            raise RuntimeError(f"Release language manifest entry is missing an .rc file name: {entry!r}")
        dlls.append(Path(rc_name).with_suffix(".dll").name)
    return tuple(sorted(dlls))


def _package_language_path(app_root: Path, platform: str, expected_language_dlls: tuple[str, ...]) -> Path:
    lang_path = app_root / "srchybrid" / platform / "lang"
    if not lang_path.is_dir():
        raise RuntimeError(f"Cannot package missing built language DLLs: {lang_path}")
    missing = [dll for dll in expected_language_dlls if not (lang_path / dll).is_file()]
    if missing:
        raise RuntimeError(f"Cannot package missing built language DLLs in {lang_path}:\n" + "\n".join(missing))
    extra = sorted(path.name for path in lang_path.glob("*.dll") if path.name not in expected_language_dlls)
    if extra:
        raise RuntimeError(f"Cannot package unexpected language DLLs in {lang_path}:\n" + "\n".join(extra))
    for dll in expected_language_dlls:
        _assert_pe_machine(lang_path / dll, platform)
    return lang_path


def _package_webserver_path(app_root: Path, build_output_root: Path) -> Path:
    webserver_path = build_output_root / "webserver"
    if webserver_path.is_dir() and any(path.is_file() for path in webserver_path.rglob("*")):
        return webserver_path
    return app_root / "srchybrid" / "webinterface"


def _copy_package_file(source_path: Path, package_root: Path, relative_destination_path: Path) -> None:
    if not source_path.is_file():
        raise RuntimeError(f"Cannot package missing file: {source_path}")
    destination_path = package_root / relative_destination_path
    _assert_path_under_root(destination_path, package_root, "release package file")
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_path, destination_path)


def _copy_directory_contents(source_path: Path, destination_path: Path) -> None:
    destination_path.mkdir(parents=True, exist_ok=True)
    for child in source_path.iterdir():
        target = destination_path / child.name
        if child.is_dir():
            shutil.copytree(child, target, dirs_exist_ok=True)
        else:
            shutil.copy2(child, target)


def _write_package_readme(package_root: Path, release_version: str, platform: str) -> None:
    """Writes the package-facing README."""

    readme_path = package_root / "README.md"
    _assert_path_under_root(readme_path, package_root, "release package README")
    asset_arch = "arm64" if platform == "ARM64" else "x64"
    readme_path.write_text(
        "\n".join(
            (
                "# eMule broadband edition",
                "",
                f"Version: {release_version}",
                f"Architecture: {asset_arch}",
                "",
                "Run `emule.exe` from this directory. The package is portable and keeps the",
                "stock eMule language DLLs under `lang/` and the legacy web template under",
                "`webserver/`.",
                "",
                "REST API documentation is included under `docs/`. Language DLLs are built",
                "from the stock eMule language resource set and are architecture-specific.",
                "",
                "MediaInfo integration remains optional. To enable audio/video metadata,",
                "install a compatible external `MediaInfo.dll` next to `emule.exe`; it is not",
                "bundled in this ZIP.",
                "",
                "This ZIP is not code-signed and does not include debug symbols.",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _write_package_release_notes(package_root: Path, release_version: str) -> None:
    """Writes concise release notes for the binary package."""

    notes_path = package_root / "RELEASE-NOTES.md"
    _assert_path_under_root(notes_path, package_root, "release package notes")
    notes_path.write_text(
        "\n".join(
            (
                "# Release Notes",
                "",
                f"eMule broadband edition {release_version} is the first public beta line",
                "for eMule BB.",
                "",
                "- Preserves stock eD2K/Kad protocol compatibility.",
                "- Ships x64 and ARM64 portable ZIP assets.",
                "- Bundles the full stock language DLL set for the selected architecture.",
                "- Includes the in-process REST API documentation used by controller integrations.",
                "- Does not bundle optional external MediaInfo runtime DLLs.",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _write_package_license_notice(package_root: Path) -> None:
    notice_path = package_root / "LICENSE-NOTICE.txt"
    _assert_path_under_root(notice_path, package_root, "release package license notice")
    notice_path.write_text(
        "\n".join(
            (
                "eMule broadband edition contains eMule-derived application code licensed under GPL-2.0-or-later.",
                "The source tree retains the per-file GPL notices from the original eMule project and eMule BB changes.",
                "Third-party libraries are linked from the canonical workspace dependency pins and retain their upstream licenses.",
                "See GPL-2.0-or-later.txt and THIRD-PARTY-NOTICES.txt in this package.",
                "For complete corresponding source, use the eMule BB source repositories "
                "at the app commit recorded in the package manifest.",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _write_package_third_party_notices(package_root: Path) -> None:
    """Writes third-party dependency notices for the bundled binary."""

    notice_path = package_root / "THIRD-PARTY-NOTICES.txt"
    _assert_path_under_root(notice_path, package_root, "release package third-party notices")
    notice_path.write_text(
        "\n".join(
            (
                "Third-party notices for eMule broadband edition",
                "",
                "The binary is built from the canonical workspace dependency pins recorded",
                "in the release manifest. The package does not redistribute separate",
                "third-party DLLs except stock eMule language resource DLLs.",
                "",
                "Linked dependencies and license families:",
                "- Crypto++: Boost Software License 1.0",
                "- id3lib: GNU Library General Public License 2.0",
                "- miniupnpc: BSD-style license from the MiniUPnP project",
                "- libpcpnatpmp: PCP/NAT-PMP client library license from the pinned fork",
                "- ResizableLib: Artistic License 2.0",
                "- zlib: zlib license",
                "- Mbed TLS / TF-PSA-Crypto: Apache-2.0 OR GPL-2.0-or-later",
                "- nlohmann/json: MIT license",
                "",
                "Complete corresponding source and full upstream license files are available",
                "from the eMule BB source repositories at the commits recorded in the",
                "release manifest.",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _write_package_gpl_text(layout: WorkspaceLayout, package_root: Path) -> None:
    """Writes the GPL-2.0-or-later license text from a pinned local dependency."""

    license_path = layout.resolve_workspace_path("repos/third_party/eMule-mbedtls/LICENSE")
    if not license_path.is_file():
        raise RuntimeError(f"Cannot package missing GPL license source: {license_path}")
    text = license_path.read_text(encoding="utf-8", errors="replace")
    start = text.find("                    GNU GENERAL PUBLIC LICENSE")
    if start < 0:
        raise RuntimeError(f"Cannot find GPL text in license source: {license_path}")
    gpl_text = text[start:].strip() + "\n"
    destination_path = package_root / "GPL-2.0-or-later.txt"
    _assert_path_under_root(destination_path, package_root, "release package GPL text")
    destination_path.write_text(gpl_text, encoding="utf-8", newline="\n")


def _write_zip(staging_root: Path, package_root: Path, zip_path: Path) -> None:
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(package_root.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(staging_root).as_posix())


def _assert_release_package_contents(zip_path: Path, expected_language_dlls: tuple[str, ...], platform: str) -> None:
    with zipfile.ZipFile(zip_path, "r") as archive:
        entry_names = [name.replace("\\", "/") for name in archive.namelist()]
        entry_set = set(entry_names)
        required_entries = (
            "eMule/emule.exe",
            "eMule/README.md",
            "eMule/RELEASE-NOTES.md",
            "eMule/LICENSE-NOTICE.txt",
            "eMule/GPL-2.0-or-later.txt",
            "eMule/THIRD-PARTY-NOTICES.txt",
            "eMule/docs/REST-API-CONTRACT.md",
            "eMule/docs/REST-API-OPENAPI.yaml",
            "eMule/docs/REST-API-PARITY-INVENTORY.md",
        )
        for required_entry in required_entries:
            if required_entry not in entry_set:
                raise RuntimeError(f"Release package is missing required entry '{required_entry}': {zip_path}")
        language_dlls = sorted(name for name in entry_names if re.fullmatch(r"eMule/lang/[^/]+\.dll", name))
        expected_language_entries = tuple(f"eMule/lang/{dll}" for dll in expected_language_dlls)
        missing_language_entries = [name for name in expected_language_entries if name not in entry_set]
        extra_language_entries = [name for name in language_dlls if name not in expected_language_entries]
        if missing_language_entries:
            raise RuntimeError("Release package is missing language DLLs:\n" + "\n".join(missing_language_entries))
        if extra_language_entries:
            raise RuntimeError("Release package contains unexpected language DLLs:\n" + "\n".join(extra_language_entries))
        for entry_name in ("eMule/emule.exe", *language_dlls):
            _assert_pe_machine_bytes(archive.read(entry_name), platform, entry_name)
        webserver_files = [name for name in entry_names if re.fullmatch(r"eMule/webserver/.+[^/]", name)]
        if not webserver_files:
            raise RuntimeError(f"Release package has no webserver payload under eMule/webserver: {zip_path}")
        forbidden_entries = [
            name
            for name in entry_names
            if re.search(r"(^|/)(Win32|x86)(/|$)", name)
            or re.search(r"\.(pdb|obj|ilk|idb|iobj|ipdb|tlog|lastbuildstate|vcxproj|filters|sln|aps|res|rc|rc2|cpp|c|h|hpp)$", name)
        ]
        if forbidden_entries:
            sample = "\n".join(forbidden_entries[:20])
            raise RuntimeError(f"Release package contains build/source artifacts:\n{sample}")
    print(f"Package content check: {zip_path} ({len(entry_names)} entries, {len(language_dlls)} language DLLs)")


def _assert_pe_machine(path: Path, platform: str) -> None:
    """Checks that one PE file matches the selected package platform."""

    if _pe_machine(path.read_bytes(), str(path)) != PE_MACHINES[platform]:
        raise RuntimeError(f"PE architecture mismatch for {path}: expected {platform}.")


def _assert_pe_machine_bytes(payload: bytes, platform: str, label: str) -> None:
    """Checks that one PE payload from a ZIP matches the selected package platform."""

    machine = _pe_machine(payload, label)
    expected = PE_MACHINES[platform]
    if machine != expected:
        raise RuntimeError(f"PE architecture mismatch for {label}: got 0x{machine:04X}, expected {platform}.")


def _pe_machine(payload: bytes, label: str) -> int:
    """Returns the COFF machine type from a PE payload."""

    if len(payload) < 0x40 or payload[:2] != b"MZ":
        raise RuntimeError(f"Not a PE file: {label}")
    pe_offset = struct.unpack_from("<I", payload, 0x3C)[0]
    if pe_offset < 0 or pe_offset + 6 > len(payload):
        raise RuntimeError(f"Invalid PE header offset in {label}")
    if payload[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise RuntimeError(f"Invalid PE signature in {label}")
    return struct.unpack_from("<H", payload, pe_offset + 4)[0]


def _app_mod_release_version(app_root: Path) -> str:
    version_header_path = app_root / "srchybrid" / "Version.h"
    if not version_header_path.is_file():
        raise RuntimeError(f"Cannot read missing app version header: {version_header_path}")
    parts: dict[str, int] = {}
    pattern = re.compile(r"^\s*#define\s+MOD_RELEASE_VERSION_(MAJOR|MINOR|PATCH)\s+(\d+)\s*$")
    for line in version_header_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            parts[match.group(1)] = int(match.group(2))
    for required_part in ("MAJOR", "MINOR", "PATCH"):
        if required_part not in parts:
            raise RuntimeError(f"Cannot find MOD_RELEASE_VERSION_{required_part} in {version_header_path}")
    return f"{parts['MAJOR']}.{parts['MINOR']}.{parts['PATCH']}"


def _assert_package_version_matches_app(app_root: Path, release_version: str) -> None:
    app_release_version = _app_mod_release_version(app_root)
    if release_version != app_release_version:
        raise RuntimeError(
            f"package release version mismatch: --release-version is '{release_version}' "
            f"but app MOD_RELEASE_VERSION is '{app_release_version}'."
        )


def _assert_path_under_root(path: Path, root: Path, label: str) -> None:
    resolved_path = path.resolve()
    resolved_root = root.resolve()
    try:
        resolved_path.relative_to(resolved_root)
    except ValueError as exc:
        raise RuntimeError(f"{label} resolved outside expected root: {resolved_path}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _zip_entry_hashes(zip_path: Path) -> dict[str, str]:
    """Returns SHA-256 hashes for every file entry in a release ZIP."""

    hashes: dict[str, str] = {}
    with zipfile.ZipFile(zip_path, "r") as archive:
        for name in sorted(archive.namelist()):
            if name.endswith("/"):
                continue
            hashes[name.replace("\\", "/")] = hashlib.sha256(archive.read(name)).hexdigest()
    return hashes

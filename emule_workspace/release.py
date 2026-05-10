"""Release package orchestration."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from .build import app_binary_path, app_property_overrides, ensure_app_dependency_artifacts, verify_app_control_flow_guard
from .build_state import BuildSession
from .config import ReleasePackageOptions, WorkspaceOptions
from .git import git_output, repo_branch, repo_head, repo_status_lines
from .layout import WorkspaceLayout
from .msbuild import env_override, invoke_msbuild_project


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
    app_root = layout.get_app_variant("main").path
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
    lang_path = _package_language_path(app_root, workspace_options.platform)
    webserver_path = _package_webserver_path(app_root, build_output_root)
    for required_path in (exe_path, lang_path, webserver_path):
        if not required_path.exists():
            raise RuntimeError(f"Cannot package missing release runtime path: {required_path}")

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
    _copy_package_file(app_root / "README.md", package_root, Path("README.md"))
    _write_package_license_notice(package_root)
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
    _assert_release_package_contents(zip_path)

    zip_hash = _sha256(zip_path)
    exe_hash = _sha256(exe_path)
    manifest = {
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
        "appCommit": repo_head(app_root),
        "buildCommit": repo_head(layout.build_repo_root),
        "toolingCommit": repo_head(layout.tooling_repo_root),
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "includedPaths": [
            "eMule/emule.exe",
            "eMule/lang",
            "eMule/webserver",
            "eMule/README.md",
            "eMule/LICENSE-NOTICE.txt",
            "eMule/docs/REST-API-CONTRACT.md",
            "eMule/docs/REST-API-OPENAPI.yaml",
            "eMule/docs/REST-API-PARITY-INVENTORY.md",
        ],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Release package: {zip_path}")
    print(f"Release manifest: {manifest_path}")
    print(f"SHA256: {zip_hash}")


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


def _package_language_path(app_root: Path, platform: str) -> Path:
    lang_path = app_root / "srchybrid" / platform / "lang"
    if not lang_path.is_dir() or next(lang_path.glob("*.dll"), None) is None:
        raise RuntimeError(f"Cannot package missing built language DLLs: {lang_path}")
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


def _write_package_license_notice(package_root: Path) -> None:
    notice_path = package_root / "LICENSE-NOTICE.txt"
    _assert_path_under_root(notice_path, package_root, "release package license notice")
    notice_path.write_text(
        "\n".join(
            (
                "eMule broadband edition contains eMule-derived application code licensed under GPL-2.0-or-later.",
                "The source tree retains the per-file GPL notices from the original eMule project and eMule BB changes.",
                "Third-party libraries are linked from the canonical workspace dependency pins and retain their upstream licenses.",
                "For complete corresponding source, use the eMule BB source repositories "
                "at the app commit recorded in the package manifest.",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _write_zip(staging_root: Path, package_root: Path, zip_path: Path) -> None:
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(package_root.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(staging_root).as_posix())


def _assert_release_package_contents(zip_path: Path) -> None:
    with zipfile.ZipFile(zip_path, "r") as archive:
        entry_names = [name.replace("\\", "/") for name in archive.namelist()]
    required_entries = (
        "eMule/emule.exe",
        "eMule/README.md",
        "eMule/LICENSE-NOTICE.txt",
        "eMule/docs/REST-API-CONTRACT.md",
        "eMule/docs/REST-API-OPENAPI.yaml",
        "eMule/docs/REST-API-PARITY-INVENTORY.md",
    )
    for required_entry in required_entries:
        if required_entry not in entry_names:
            raise RuntimeError(f"Release package is missing required entry '{required_entry}': {zip_path}")
    language_dlls = [name for name in entry_names if re.fullmatch(r"eMule/lang/[^/]+\.dll", name)]
    if not language_dlls:
        raise RuntimeError(f"Release package has no language DLLs under eMule/lang: {zip_path}")
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

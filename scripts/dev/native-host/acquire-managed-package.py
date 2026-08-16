#!/usr/bin/env python3
"""Acquire and extract one exact locked npm archive without running package code."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import http.client
import importlib.util
import ipaddress
import os
import pathlib
import re
import signal
import socket
import ssl
import stat
import time
from types import ModuleType
from typing import NoReturn
from urllib.parse import SplitResult, urlsplit


REGISTRY_HOST = "registry.npmjs.org"
REGISTRY_PORT = 443
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_HEADER_BYTES = 64 * 1024
CHUNK_BYTES = 1024 * 1024
CONNECT_TIMEOUT_SECONDS = 20.0
READ_TIMEOUT_SECONDS = 30.0
MAX_DOWNLOAD_SECONDS = 600.0
SAFE_PACKAGE = re.compile(r"^(?:@[a-z0-9._-]+/)?[a-z0-9._-]+$")
SAFE_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.-]+)?$")
SAFE_INTEGRITY = re.compile(r"^sha512-([A-Za-z0-9+/]+={0,2})$")
SAFE_IDENTITY = re.compile(r"^[0-9]+:[0-9]+$")
SAFE_ERROR = re.compile(r"^[a-z0-9-]+$")


class AcquisitionFailure(Exception):
    """A closed, path-redacted acquisition failure."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code if SAFE_ERROR.fullmatch(code) else "unexpected-failure"


class ClosedArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        del message
        fail("argument-policy")


def fail(code: str) -> NoReturn:
    raise AcquisitionFailure(code)


def raise_network_timeout(_signum: int, _frame: object) -> NoReturn:
    fail("network-timeout")


def identity(metadata: os.stat_result) -> str:
    return f"{metadata.st_dev}:{metadata.st_ino}"


def stable_file_identity(
    metadata: os.stat_result,
) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
        metadata.st_nlink,
    )


def directory_flags() -> int:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def anonymous_file_flags() -> int:
    flags = os.O_RDWR | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def clear_network_environment() -> None:
    # HTTPSConnection does not implement proxy discovery, but clearing the
    # environment also prevents CA, key-log, resolver, and future stdlib
    # behavior from silently expanding this closed network boundary.
    os.environ.clear()
    os.environ["LC_ALL"] = "C"


def validate_identity(value: str, code: str) -> str:
    if SAFE_IDENTITY.fullmatch(value) is None:
        fail(code)
    return value


def open_private_directory(
    path: str,
    expected_identity: str,
    code: str,
) -> tuple[int, os.stat_result]:
    validate_identity(expected_identity, code)
    if (
        not path.startswith("/")
        or path == "/"
        or any(character in path for character in "\n\r\t")
    ):
        fail(code)
    try:
        descriptor = os.open(path, directory_flags())
        metadata = os.fstat(descriptor)
    except OSError:
        fail(code)
    mode = stat.S_IMODE(metadata.st_mode)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or mode != 0o700
        or identity(metadata) != expected_identity
    ):
        os.close(descriptor)
        fail(code)
    return descriptor, metadata


def require_directory_identity(
    descriptor: int,
    expected_identity: str,
    code: str,
) -> os.stat_result:
    try:
        metadata = os.fstat(descriptor)
    except OSError:
        fail(code)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or identity(metadata) != expected_identity
    ):
        fail(code)
    return metadata


def require_directory_path_identity(
    path: str,
    expected_identity: str,
    code: str,
) -> os.stat_result:
    try:
        metadata = os.stat(path, follow_symlinks=False)
    except OSError:
        fail(code)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or identity(metadata) != expected_identity
    ):
        fail(code)
    return metadata


def canonical_url(package_name: str, package_version: str) -> str:
    leaf = package_name.rsplit("/", 1)[-1]
    return (
        f"https://{REGISTRY_HOST}/{package_name}/-/"
        f"{leaf}-{package_version}.tgz"
    )


def validate_source(
    url: str,
    package_name: str,
    package_version: str,
) -> SplitResult:
    if SAFE_PACKAGE.fullmatch(package_name) is None:
        fail("package-name-policy")
    package_parts = package_name.split("/")
    if any(part in (".", "..", "@.", "@..") for part in package_parts):
        fail("package-name-policy")
    if SAFE_VERSION.fullmatch(package_version) is None:
        fail("package-version-policy")
    expected = canonical_url(package_name, package_version)
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        fail("source-policy")
    if (
        url != expected
        or parsed.scheme != "https"
        or parsed.netloc != REGISTRY_HOST
        or parsed.hostname != REGISTRY_HOST
        or port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path != urlsplit(expected).path
    ):
        fail("source-policy")
    return parsed


def expected_sri_digest(integrity: str) -> bytes:
    match = SAFE_INTEGRITY.fullmatch(integrity)
    if match is None:
        fail("integrity-policy")
    encoded = match.group(1)
    try:
        decoded = base64.b64decode(encoded, validate=True)
    except ValueError:
        fail("integrity-policy")
    if (
        len(decoded) != hashlib.sha512().digest_size
        or base64.b64encode(decoded).decode("ascii") != encoded
    ):
        fail("integrity-policy")
    return decoded


def tls_context() -> ssl.SSLContext:
    try:
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        if hasattr(ssl, "OP_NO_COMPRESSION"):
            context.options |= ssl.OP_NO_COMPRESSION
        return context
    except (OSError, ssl.SSLError, ValueError):
        fail("tls-policy")


def validate_connected_peer(connection: http.client.HTTPSConnection) -> None:
    connected = connection.sock
    if connected is None:
        fail("peer-policy")
    try:
        address = ipaddress.ip_address(connected.getpeername()[0])
    except (OSError, ValueError, TypeError, IndexError):
        fail("peer-policy")
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    if not address.is_global:
        fail("peer-policy")
    connected.settimeout(READ_TIMEOUT_SECONDS)


def open_response(parsed: SplitResult) -> tuple[
    http.client.HTTPSConnection, http.client.HTTPResponse
]:
    connection = http.client.HTTPSConnection(
        REGISTRY_HOST,
        REGISTRY_PORT,
        timeout=CONNECT_TIMEOUT_SECONDS,
        context=tls_context(),
    )
    try:
        connection.connect()
        validate_connected_peer(connection)
        connection.putrequest(
            "GET", parsed.path, skip_host=True, skip_accept_encoding=True
        )
        connection.putheader("Host", REGISTRY_HOST)
        connection.putheader("User-Agent", "MAINFRAME-managed-host-acquisition/1")
        connection.putheader("Accept", "application/octet-stream")
        connection.putheader("Accept-Encoding", "identity")
        connection.putheader("Connection", "close")
        connection.endheaders()
        response = connection.getresponse()
        return connection, response
    except BaseException:
        connection.close()
        raise


def single_header(response: http.client.HTTPResponse, name: str) -> str | None:
    values = response.headers.get_all(name, [])
    if len(values) > 1:
        fail("response-policy")
    return values[0] if values else None


def validate_response(response: http.client.HTTPResponse) -> int | None:
    try:
        header_bytes = response.headers.as_bytes()
    except (OSError, UnicodeError, ValueError):
        fail("response-policy")
    if len(header_bytes) > MAX_HEADER_BYTES:
        fail("response-policy")
    if 300 <= response.status <= 399:
        fail("redirect-not-allowed")
    if response.status != 200:
        fail("http-status")

    content_encoding = single_header(response, "Content-Encoding")
    if content_encoding is not None and content_encoding.lower() != "identity":
        fail("response-policy")
    if single_header(response, "Content-Range") is not None:
        fail("response-policy")
    transfer_encoding = single_header(response, "Transfer-Encoding")
    content_length = single_header(response, "Content-Length")
    if transfer_encoding is not None:
        if transfer_encoding.lower() != "chunked" or content_length is not None:
            fail("response-policy")
    if content_length is None:
        return None
    if re.fullmatch(r"[1-9][0-9]*", content_length) is None:
        fail("response-policy")
    declared = int(content_length)
    if declared > MAX_ARCHIVE_BYTES:
        fail("archive-too-large")
    return declared


def create_anonymous_scratch(
    scratch_descriptor: int,
    scratch_identity: str,
) -> int:
    for _ in range(64):
        name = f".acquire.{os.urandom(12).hex()}"
        created_identity = ""
        try:
            descriptor = os.open(
                name, anonymous_file_flags(), 0o600, dir_fd=scratch_descriptor
            )
        except FileExistsError:
            continue
        except OSError:
            fail("scratch-create-failed")
        try:
            created = os.fstat(descriptor)
            created_identity = identity(created)
            if (
                not stat.S_ISREG(created.st_mode)
                or created.st_uid != os.geteuid()
                or created.st_nlink != 1
                or stat.S_IMODE(created.st_mode) != 0o600
            ):
                fail("scratch-policy")
            os.unlink(name, dir_fd=scratch_descriptor)
            os.fsync(scratch_descriptor)
            unlinked = os.fstat(descriptor)
            if (
                identity(unlinked) != identity(created)
                or unlinked.st_nlink != 0
                or stat.S_IMODE(unlinked.st_mode) != 0o600
            ):
                fail("scratch-policy")
            require_directory_identity(
                scratch_descriptor, scratch_identity, "scratch-policy"
            )
            return descriptor
        except BaseException:
            try:
                current = os.stat(
                    name, dir_fd=scratch_descriptor, follow_symlinks=False
                )
                if created_identity and identity(current) == created_identity:
                    os.unlink(name, dir_fd=scratch_descriptor)
                    os.fsync(scratch_descriptor)
            except OSError:
                pass
            os.close(descriptor)
            raise
    fail("scratch-create-failed")


def load_extractor() -> ModuleType:
    helper = pathlib.Path(__file__).absolute().with_name(
        "extract-managed-package.py"
    )
    try:
        metadata = os.lstat(helper)
    except OSError:
        fail("extractor-policy")
    if (
        not stat.S_ISREG(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid not in (0, os.geteuid())
        or stat.S_IMODE(metadata.st_mode) & 0o7022
    ):
        fail("extractor-policy")
    try:
        spec = importlib.util.spec_from_file_location(
            "_mainframe_managed_package_extractor", helper
        )
        if spec is None or spec.loader is None:
            fail("extractor-policy")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    except AcquisitionFailure:
        raise
    except BaseException:
        fail("extractor-policy")
    if not callable(getattr(module, "verify_integrity", None)) or not callable(
        getattr(module, "extract", None)
    ):
        fail("extractor-policy")
    return module


def stream_archive(
    response: http.client.HTTPResponse,
    descriptor: int,
    declared_length: int | None,
    expected_digest: bytes,
) -> int:
    digest = hashlib.sha512()
    total = 0
    deadline = time.monotonic() + MAX_DOWNLOAD_SECONDS
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            fail("network-timeout")
        chunk = response.read(CHUNK_BYTES)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_ARCHIVE_BYTES:
            fail("archive-too-large")
        if declared_length is not None and total > declared_length:
            fail("response-policy")
        digest.update(chunk)
        view = memoryview(chunk)
        while view:
            try:
                written = os.write(descriptor, view)
            except OSError:
                fail("scratch-write-failed")
            if written <= 0:
                fail("scratch-write-failed")
            view = view[written:]
    if total == 0:
        fail("empty-archive")
    if declared_length is not None and total != declared_length:
        fail("response-policy")
    if not hmac.compare_digest(digest.digest(), expected_digest):
        fail("integrity-mismatch")
    return total


def verify_and_extract_same_descriptor(
    extractor: ModuleType,
    descriptor: int,
    destination: pathlib.Path,
    destination_identity: str,
    integrity: str,
    package_name: str,
    package_version: str,
) -> None:
    before_reverification = stable_file_identity(os.fstat(descriptor))
    try:
        extractor.verify_integrity(descriptor, integrity)
    except BaseException:
        fail("integrity-reverification-failed")
    authenticated = stable_file_identity(os.fstat(descriptor))
    if authenticated != before_reverification:
        fail("archive-identity-changed")
    try:
        extractor.extract(
            descriptor,
            destination,
            package_name,
            package_version,
            destination_identity,
        )
    except BaseException:
        fail("archive-policy")
    if stable_file_identity(os.fstat(descriptor)) != authenticated:
        fail("archive-identity-changed")


def acquire(
    url: str,
    scratch_directory: str,
    scratch_identity: str,
    destination_directory: str,
    destination_identity: str,
    integrity: str,
    package_name: str,
    package_version: str,
) -> None:
    parsed = validate_source(url, package_name, package_version)
    expected_digest = expected_sri_digest(integrity)
    scratch, _ = open_private_directory(
        scratch_directory, scratch_identity, "scratch-policy"
    )
    destination = -1
    archive = -1
    connection: http.client.HTTPSConnection | None = None
    response: http.client.HTTPResponse | None = None
    try:
        destination, _ = open_private_directory(
            destination_directory,
            destination_identity,
            "destination-policy",
        )
        try:
            if os.listdir(destination):
                fail("destination-not-empty")
        except OSError:
            fail("destination-policy")
        extractor = load_extractor()
        archive = create_anonymous_scratch(scratch, scratch_identity)
        require_directory_path_identity(
            scratch_directory, scratch_identity, "scratch-policy"
        )
        require_directory_path_identity(
            destination_directory,
            destination_identity,
            "destination-policy",
        )
        previous_alarm_handler = signal.getsignal(signal.SIGALRM)
        signal.signal(signal.SIGALRM, raise_network_timeout)
        previous_alarm = signal.setitimer(
            signal.ITIMER_REAL, MAX_DOWNLOAD_SECONDS
        )
        try:
            connection, response = open_response(parsed)
            declared_length = validate_response(response)
            total = stream_archive(
                response, archive, declared_length, expected_digest
            )
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0.0)
            signal.signal(signal.SIGALRM, previous_alarm_handler)
            if previous_alarm[0] > 0.0:
                signal.setitimer(
                    signal.ITIMER_REAL, previous_alarm[0], previous_alarm[1]
                )
        try:
            os.fsync(archive)
            os.fchmod(archive, 0o400)
            downloaded = os.fstat(archive)
        except OSError:
            fail("scratch-write-failed")
        if (
            not stat.S_ISREG(downloaded.st_mode)
            or downloaded.st_uid != os.geteuid()
            or downloaded.st_nlink != 0
            or downloaded.st_size != total
            or stat.S_IMODE(downloaded.st_mode) != 0o400
        ):
            fail("scratch-policy")
        require_directory_identity(scratch, scratch_identity, "scratch-policy")
        require_directory_identity(
            destination, destination_identity, "destination-policy"
        )
        require_directory_path_identity(
            scratch_directory, scratch_identity, "scratch-policy"
        )
        require_directory_path_identity(
            destination_directory,
            destination_identity,
            "destination-policy",
        )
        verify_and_extract_same_descriptor(
            extractor,
            archive,
            pathlib.Path(destination_directory),
            destination_identity,
            integrity,
            package_name,
            package_version,
        )
        require_directory_identity(scratch, scratch_identity, "scratch-policy")
        require_directory_identity(
            destination, destination_identity, "destination-policy"
        )
        require_directory_path_identity(
            scratch_directory, scratch_identity, "scratch-policy"
        )
        require_directory_path_identity(
            destination_directory,
            destination_identity,
            "destination-policy",
        )
    finally:
        if response is not None:
            response.close()
        if connection is not None:
            connection.close()
        if archive >= 0:
            os.close(archive)
        if destination >= 0:
            os.close(destination)
        os.close(scratch)


def parse_args() -> argparse.Namespace:
    parser = ClosedArgumentParser(description=__doc__, add_help=False)
    parser.add_argument("url")
    parser.add_argument("scratch_directory")
    parser.add_argument("scratch_identity")
    parser.add_argument("destination_directory")
    parser.add_argument("destination_identity")
    parser.add_argument("integrity")
    parser.add_argument("package_name")
    parser.add_argument("package_version")
    return parser.parse_args()


def _main() -> None:
    args = parse_args()
    clear_network_environment()
    acquire(
        args.url,
        args.scratch_directory,
        args.scratch_identity,
        args.destination_directory,
        args.destination_identity,
        args.integrity,
        args.package_name,
        args.package_version,
    )


def main() -> int:
    try:
        _main()
        return 0
    except AcquisitionFailure as error:
        code = error.code
    except (socket.timeout, TimeoutError):
        code = "network-timeout"
    except socket.gaierror:
        code = "dns-failed"
    except ssl.SSLError:
        code = "tls-failed"
    except http.client.HTTPException:
        code = "network-failed"
    except ConnectionError:
        code = "network-failed"
    except OSError:
        code = "operating-system-failure"
    except KeyboardInterrupt:
        code = "interrupted"
    except BaseException:
        code = "unexpected-failure"
    try:
        os.write(
            2, f"managed package acquisition failed: {code}\n".encode("ascii")
        )
    except OSError:
        pass
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

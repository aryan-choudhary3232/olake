# Contributing to OLake

We truly value and appreciate all contributions — every effort makes a difference, and proper credit will always be given.  
To ensure consistency, we follow a structured contribution process. All guidelines and details have been consolidated into the official OLake documentation. Please refer to the links below for more information:

- [Contribute To OLake](https://olake.io/docs/community/contributing)
- [How To Raise A PR](https://olake.io/docs/community/issues-and-prs)
- [Setting Up A Development Environment](https://olake.io/docs/community/setting-up-a-dev-env)
- **Running tests locally** — run `make help` for all local database-stack and test targets (e.g. `make test.integration.<driver>` for a driver's whole suite, `make test.discover.<driver>` / `make test.sync.<driver>` / `make test.2pc.<driver>` for one of them, `make test.unit`)
- **Backward compatibility tests** — see
  [tests/testutils/compatibility/README.md](tests/testutils/compatibility/README.md)
  for what the suite asserts, how `constants/state-versions.json` drives it,
  and what a PR introducing a state version has to add

## Building release images

`make docker.<driver>.build` builds the image the default way (`BINARIES=source`): Go compiles inside Docker. Local builds and the test suites use this path.

Releases build the binaries on the host first and the image only copies them in (`BINARIES=dist`). The release workflow (`.github/workflows/build-and-release-driver.yml`) does this; to build the same image locally:

```bash
# 1. The driver binaries for its platforms (drivers/platforms.conf, or PLATFORMS=...) and the Iceberg writer jar
make iceberg.jar dist.<driver> PLATFORMS=linux/amd64

# 2. The image, copying dist/<driver>/<os>/<arch>/ instead of compiling
docker buildx build --platform linux/amd64 \
  --build-arg BINARIES=dist \
  --build-arg DRIVER_NAME=<driver> \
  --build-arg DRIVER_VERSION=<version> \
  --load -t olakego/source-<driver>:<version> .
```

`dist.<driver>` writes `dist/<driver>/<os>/<arch>/` with the `olake` binary, the driver's runtime files (`overlay/`) and its extra runtime packages (`runtime-packages`). Every driver cross-compiles except `db2`, which uses cgo: build it on a Linux host of the target platform.

---

## ❄️ Social Winter of Code (SWoC 2026) @OLake

OLake is officially open for **Social Winter of Code 2026 contributions**! 🚀

If you’re participating in SWoC 2026, look out for issues labeled:

* **`SWoC26`**
* **`beginner`**
* **`intermediate`**
* **`advanced`**

These labels help you choose issues based on your experience level.
We welcome all kinds of contributions — bug fixes, documentation improvements, tests, and feature enhancements.

👉 [Check our open issues here](../../issues)

---
Let’s hack, learn, and grow together this Hacktoberfest. Happy contributing & happy engineering! ⚡ 
---

## Getting Help

For any questions, concerns, or queries:
- Start a discussion on our [**Slack**](https://olake.io/slack/) channel.  
- Check [GitHub Discussions](https://github.com/datazip-inc/olake-go/discussions) for ongoing conversations.  
- Don’t hesitate to open an issue if something is unclear.

---

### 💡 We look forward to your feedback and contributions to improve this project!
<!----variables----> 
[CLA]: https://docs.google.com/forms/d/e/1FAIpQLSdze2q6gn81fmbIp2bW5cIpAXcpv7Y5OQjQyXflNvoYWiO4OQ/viewform

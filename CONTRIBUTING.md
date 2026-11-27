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

Releases build the image the same way as `make docker.<driver>.build` and the test suites: Go compiles inside Docker. The release workflow (`.github/workflows/build-and-release-driver.yml`) builds each platform on a runner of that architecture, so nothing runs under QEMU. To build the same image locally:

```bash
# 1. The Iceberg writer jar the image copies in
make iceberg.jar

# 2. The image for one platform (drivers/platforms.conf lists each driver's platforms)
docker buildx build --platform linux/amd64 \
  --build-arg DRIVER_NAME=<driver> \
  --build-arg DRIVER_VERSION=<version> \
  --load -t olakego/source-<driver>:<version> .
```

Every driver cross-compiles except `db2`, which uses cgo against IBM's x86-64 clidriver: build it for `linux/amd64` only.

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

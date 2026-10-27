// Temporary: pulls a known-vulnerable gin version to test Dependabot -> Teams alerts.
// Delete this folder after the test.
module example.com/dependabot-test

go 1.21

require github.com/gin-gonic/gin v1.6.0

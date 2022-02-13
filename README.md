# Install

```
brew tap prx/dev-tools
brew install prx-dev-tools
```

# Contribute

After you've made your changes and committed them to the main branch, create a new release in GitHub, with a new version tag (in the format `v1.2.3`). Once the release has been created, a GitHub action will automatically update the formula file to match the newly-released version and update the SHA 256 hash.

This does mean that any given release will actually include the formula file for the _previous_ version. This does not matter.

# Install

```
brew tap prx/dev-tools
brew install prx-dev-tools
```

# Configuration

You can optionally configure these scripts to use certain AWS profiles and dev tools:

```sh
echo "export PRX_SSH_KEY=~/.ssh/id_ed25519_prx_developer" >> ~/.bash_profile
echo "export PRX_AWS_PROFILE=prx-default" >> ~/.bash_profile
```

# Contribute

After you've made your changes and committed them to the main branch, create a new release in GitHub, with a new version tag (in the format `v1.2.3`). Once the release has been created, a GitHub action will automatically update the formula file to match the newly-released version and update the SHA 256 hash.

This does mean that any given release will actually include the formula file for the _previous_ version. This does not matter.

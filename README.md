# Homebrew tap for Stay

This tap installs Stay from target-native binary archives published in the
[Stay GitHub Releases](https://github.com/nevdelap/stay/releases). It does not
compile Stay from source. The formula installs `tmux` as a runtime dependency;
Stay requires tmux 3.6 or newer.

```sh
brew tap nevdelap/stay
brew install nevdelap/stay/stay
```

The formula supports macOS ARM64, macOS Intel, Linux ARM64, and Linux x86_64.

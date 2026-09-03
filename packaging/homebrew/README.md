# Homebrew casks

Do not hand-edit a checksum in the production tap. `scripts/release.sh` calls `scripts/generate-casks.sh` after the final stapled ZIP exists and generates either `broccoli.rb` or `broccoli@beta.rb` with the exact SHA-256 and immutable GitHub Release URL.

The local update harness generates a separate temporary cask pointing to `127.0.0.1`. It never reads or changes a production cask or tap checkout.


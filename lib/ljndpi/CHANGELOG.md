# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [v0.1.0] - 2017-03-21
### Changed
- License changed from MIT/X11 to the Apache License 2.0

## [v0.0.3] - 2016-07-23
### Added
* Support using version 1.8 of `libndpi`.
* Values of type `ndpi.protocol_bitmask` now have a `__tostring` metamethod.
* The module is now installable using [LuaRocks](https://luarocks.org).

## [v0.0.2] - 2016-02-29
### Fixed
* Avoid calls to `ffi.gc()` passing `nil` as second argument for flows and
  identifiers.

## v0.0.1 - 2016-01-24
* First release.

[Unreleased]: https://github.com/aperezdc/ljndpi/compare/v0.1.0...HEAD
[v0.1.0]: https://github.com/aperezdc/ljndpi/compare/v0.0.3...v0.1.0
[v0.0.3]: https://github.com/aperezdc/ljndpi/compare/v0.0.2...v0.0.3
[v0.0.2]: https://github.com/aperezdc/ljndpi/compare/v0.0.1...v0.0.2

# AGENTS.md

Header-only C++14 numerical array library (lazy broadcasting). All public code lives in `include/xtensor/` (namespace `xt`); the only build output is an INTERFACE target `xtensor` plus a single-include `build/xtensor.hpp`.

## Fork context

This is a fork pinning the `0.25.0` release (`XTENSOR_VERSION_*` in `include/xtensor/xtensor_config.hpp`) because upstream xtensor >= 0.26 requires C++17/20. Keep the **C++14 baseline and the 0.25.0 public interfaces** intact — do not merge upstream >= 0.26 changes or introduce C++17/20-only features into public headers, even under `CPP17`/`CPP20` build options.

## Build & test

- Tests use **doctest**, not GTest — README.md and docs/source/dev-build-options.rst still say gtest (stale). The `DOWNLOAD_GTEST` / `GTEST_SRC_DIR` options are dead; `test/CMakeLists.txt` requires `find_package(doctest REQUIRED)`.
- `environment-dev.yml` (conda/mamba, conda-forge) provides everything needed: cmake, ninja, xtl=0.7.5, xsimd=13.2.0, nlohmann_json, doctest=2.4.7, pre-commit.
- Full suite:
  ```bash
  mamba env create -f environment-dev.yml
  cmake -G Ninja -Bbuild -DBUILD_TESTS=ON
  cmake --build build --target test_xtensor_lib --parallel 8
  ctest -R ^xtest$ --output-on-failure
  ```
- Run one test file: each `test/test_*.cpp` is its own executable plus `x<name>` custom target, e.g. `cmake --build build --target xtest_xarray` (or `ctest -R test_xarray`). `xtest` / `xbenchmark` / `xpowerbench` are aggregate custom targets.
- Test builds add `-march=native` and `-Wextra -Wconversion ...` on GCC/Clang; `-Werror` via `-DXTENSOR_ENABLE_WERROR=ON`.
- CI (`.github/workflows/*`) covers the feature flags; check these to reproduce configs: `XTENSOR_ENABLE_ASSERT`, `DEFAULT_COLUMN_MAJOR`, `XTENSOR_USE_OPENMP`, `XTENSOR_DISABLE_EXCEPTIONS`, `XTENSOR_USE_XSIMD`, `CPP17`, `XTENSOR_USE_TBB`. **XTENSOR_USE_TBB and XTENSOR_USE_OPENMP are mutually exclusive** (CMake `FATAL`). xsimd requires v11+, TBB needs `-DTBB_INCLUDE_DIR/-DTBB_LIBRARY`.

## Generated test code — do not hand-edit

`test/test_extended_broadcast_view.cpp`, `test_extended_xhistogram.cpp`, `test_extended_xmath_interp.cpp`, `test_extended_xmath_reducers.cpp`, `test_extended_xsort.cpp` are generated from `test/files/cppy_source/*.cppy` by `test/files/preprocess.py` (needs python3 + numpy). Edit the `.cppy`, regenerate with `cmake --build build --target preprocess_cppy`, and commit both. The generated files carry a "do not modify directly" header.

## Lint & formatting

- `pre-commit run --all-files` (mirrors CI's static-analysis.yml): clang-format on `.*\.[hc]pp`, JSON/YAML formatting, trailing whitespace, tabs forbidden.
- `.clang-format` is the canonical style. Format a header before editing if you touch layout.

## Codebase facts an agent might miss

- C++14 baseline; `CPP17`/`CPP20` CMake options enable newer standards.
- `include/xtensor/xtensor_config.hpp` holds `XTENSOR_VERSION_{MAJOR,MINOR,PATCH}` — CMake parses it for the project version and the release checklist (docs/source/releasing.rst) says to bump it there.
- Single-include `build/xtensor.hpp` is generated at configure time from `XTENSOR_HEADERS` but **excludes** xexpression_holder, xjson, xmime, xnpy — those four headers must be included explicitly by users.
- xsimd SIMD acceleration is off by default; consumers must define `XTENSOR_USE_XSIMD` *before* any xtensor include.
- `XTENSOR_DEFAULT_LAYOUT` / `XTENSOR_DEFAULT_TRAVERSAL` macros are testing-only (strongly discouraged in user code, per docs/source/dev-build-options.rst).
- `check_circular.py` (tools/) verifies no circular `#include "..."` between headers; useful sanity check after header edits.

## Docs

`cd docs && make html` needs doxygen + sphinx + breathe (see docs/source/dev-build-options.rst). Changelog is docs/source/changelog.rst.

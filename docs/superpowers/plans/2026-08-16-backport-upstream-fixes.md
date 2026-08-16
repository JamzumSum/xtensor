# Backport Upstream Bug-Fix Commits to xtensor 0.25.0 Fork

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backport 12 independent, C++14-compatible bug fixes from upstream xtensor master (post-0.25.0) into this fork, each with its own regression test, without changing public APIs or the C++14 baseline.

**Architecture:** This is a header-only C++14 library. Each fix is a small, self-contained edit to one or two public headers in `include/xtensor/` plus a regression test appended to the corresponding `test/test_*.cpp`. All fixes are ported verbatim from upstream commits (paths mapped from the upstream `include/xtensor/{io,views,core,generators,containers,misc}/` layout to this fork's flat `include/xtensor/` layout) except two that require small C++14 adaptations. Each task follows strict TDD: write test → confirm it fails/crashes on current code → apply fix → confirm green → commit.

**Tech Stack:** C++14, CMake/Ninja, doctest (not gtest), xtl 0.7.5, mamba/conda env `environment-dev.yml`.

---

## Context an engineer must know

- **This is a fork of xtensor pinned at 0.25.0.** Upstream xtensor >= 0.26 requires C++17/20, so we port individual fixes, never merge upstream wholesale. Do NOT introduce C++17/20 features (no `if constexpr`, no `std::apply`, no `std::remove_cvref_t`, no concepts). Use the C++14 equivalents shown in each task.
- **Tests use doctest**, despite README.md / docs saying gtest. Each `test/test_*.cpp` builds as its own executable plus an `x<name>` aggregate target. `test/CMakeLists.txt` requires `find_package(doctest REQUIRED)`; `DOWNLOAD_GTEST` is dead.
- **Build/test commands** (mirror CI: `.github/workflows/linux.yml`):
  ```bash
  mamba env create -f environment-dev.yml
  cmake -G Ninja -Bbuild -DBUILD_TESTS=ON
  cmake --build build --target test_xtensor_lib --parallel 8   # full aggregate
  ctest -R ^xtest$ --output-on-failure
  ```
  Single test file: `cmake --build build --target xtest_xnpy` (target `x<name>` = `xtest_<testfilename>`). Run just one test case with `./build/test/test_xnpy -tc="xnpy.load_long_header_length"`.
- **Warning flags:** test builds add `-march=native -Wextra -Wconversion -Wno-sign-conversion -Wold-style-cast ...` on GCC/Clang; `-Werror` via `-DXTENSOR_ENABLE_WERROR=ON`. Our changes must be warning-clean under these flags.
- **Pre-commit:** `pre-commit run --all-files` runs clang-format (`.*\.[hc]pp`), trailing-whitespace, tab-forbidden, etc. `.clang-format` is canonical. Format edited files before committing.
- **Do not hand-edit generated files** `test/test_extended_*.cpp` (they come from `test/files/cppy_source/*.cppy`). None of these tasks touch them.
- All 12 fixes here were verified by the plan author against the fork source: red → green confirmed for each regression test, and the fixed headers compile clean under the CI warning flags.

## File structure

**Headers modified (one fix each unless noted):**
- `include/xtensor/xnpy.hpp` — #2889 header-length byte parse (Task 1)
- `include/xtensor/xcsv.hpp` — #2904 cell trim + 8-bit `lexical_cast` (Task 2)
- `include/xtensor/xmath.hpp` — #2909 `clip` bound handling (Task 3)
- `include/xtensor/xrandom.hpp` — #2917 `poisson`/`geometric` default `T` (Task 4)
- `include/xtensor/xaccessible.hpp` — #2865 conditional `noexcept` on `size()` (Task 5)
- `include/xtensor/xcontainer.hpp` — #2907 `resize` dimension precondition (Task 6)
- `include/xtensor/xslice.hpp` — #2927 `xstepped_range` size-underflow guard (Task 7)
- `include/xtensor/xmanipulation.hpp` — #2920 roll axis bounds + #2922 roll zero-length (Tasks 8, 9)
- `include/xtensor/xbuilder.hpp` — #2926 warning cleanup, no test (Task 10)
- `include/xtensor/xview.hpp` — #2896 leading-newaxis assignment (Task 11)
- `include/xtensor/xexpression.hpp` — #2918 `xshared_expression` linear iterators (Task 12)

**Tests modified:** `test/test_xnpy.cpp`, `test/test_xcsv.cpp`, `test/test_xmath.cpp`, `test/test_xrandom.cpp`, `test/test_xassign.cpp`, `test/test_xview.cpp`, `test/test_xmanipulation.cpp`, `test/test_xexpression.cpp`.

**NOT backported (investigated, not applicable):**
- #2912 `xt::drop` with variables — the fork's `drop(T i)` integral overload takes the arg by value, so `const size_t index; xt::drop(index)` already works. Verified: upstream's test passes on unmodified fork code.
- #2908 reverse iterators / #2897 vstack-fixed-shape / #2913 xfunction lambda return type — depend on post-0.25.0 refactors (new `index_mapper.hpp`, std::apply-based xfunction) that do not exist in this fork.

---

## Setup task: configure the build

**Files:** none.

- [ ] **Step 1: Create the conda env (once)**

```bash
mamba env create -f environment-dev.yml
mamba activate xtensor
```

- [ ] **Step 2: Configure the build (once)**

```bash
cmake -G Ninja -Bbuild -DBUILD_TESTS=ON
```

Expected: configuration succeeds; last status line prints the xtensor version (`0.25.0`) and finds `xtl` and `doctest`.

- [ ] **Step 3: Smoke-build one test target**

```bash
cmake --build build --target xtest_xnpy --parallel 8
./build/test/test_xnpy
```

Expected: builds and all 4 existing `xnpy.*` tests pass. This confirms the toolchain before you start.

---

## Task 1: Fix NPY v1.0 header-length byte parse (#2889)

**Files:**
- Modify: `include/xtensor/xnpy.hpp:486` and `include/xtensor/xnpy.hpp:506-507`
- Test: `test/test_xnpy.cpp`

**Background:** `read_header_1_0`/`read_header_2_0` read the little-endian header length into `char[]`, then combine with `uint16_t(char << 0) | uint16_t(char << 8)`. When a `char` has the MSB set (header ≥ 128 bytes, e.g. 246 → `0xF6`), the shift promotes to `int` with sign extension and the length is misread (246 becomes 65526), so the header parse throws.

- [ ] **Step 1: Write the failing test**

Append inside `namespace xt { ... }` at the end of `test/test_xnpy.cpp` (after the last `}` of the existing tests, but before the closing `}` of namespace `xt`):

```cpp
    TEST(xnpy, load_long_header_length)
    {
        const char magic[] = "\x93NUMPY";
        const unsigned char version[2] = {1, 0};
        const std::size_t header_len = 246;
        std::string header = "{'descr': '" + detail::build_typestring<std::int64_t>() + "', 'fortran_order': False, 'shape': (3,), }";
        header.resize(header_len - 1, ' ');
        header += '\n';

        std::stringstream ss;
        ss.write(magic, 6);
        ss.write(reinterpret_cast<const char*>(version), 2);
        ss.put(char(header_len & 0xff));
        ss.put(char((header_len >> 8) & 0xff));
        ss.write(header.data(), static_cast<std::streamsize>(header.size()));

        std::int64_t data[3] = {10, 20, 30};
        ss.write(reinterpret_cast<const char*>(data), sizeof(data));

        auto loaded = load_npy<std::int64_t>(ss);
        xarray<std::int64_t> expected = {10, 20, 30};
        EXPECT_TRUE(all(equal(loaded, expected)));
    }
```

The file already includes `<cstdint>`, `<fstream>` and `"xtensor/xarray.hpp"`, `"xtensor/xnpy.hpp"` — no new includes needed (add `#include <sstream>` if not already transitively present).

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xnpy --parallel 8
./build/test/test_xnpy -tc="xnpy.load_long_header_length"
```

Expected: FAIL with `ERROR: test case THREW exception: invalid header` (the misread 65526-byte header never ends in `\n`).

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xnpy.hpp`, replace inside `read_header_1_0` (line ~486):

```cpp
            uint16_t header_length = uint16_t(header_len_le16[0] << 0) | uint16_t(header_len_le16[1] << 8);
```

with:

```cpp
            uint16_t header_b0 = static_cast<uint16_t>(static_cast<uint8_t>(header_len_le16[0]));
            uint16_t header_b1 = static_cast<uint16_t>(static_cast<uint8_t>(header_len_le16[1])) << 8;
            uint16_t header_length = header_b0 | header_b1;
```

and inside `read_header_2_0` (lines ~506-507), replace:

```cpp
            uint32_t header_length = uint32_t(header_len_le32[0] << 0) | uint32_t(header_len_le32[1] << 8)
                                     | uint32_t(header_len_le32[2] << 16) | uint32_t(header_len_le32[3] << 24);
```

with:

```cpp
            uint32_t header_b0 = static_cast<uint32_t>(static_cast<uint8_t>(header_len_le32[0]));
            uint32_t header_b1 = static_cast<uint32_t>(static_cast<uint8_t>(header_len_le32[1])) << 8;
            uint32_t header_b2 = static_cast<uint32_t>(static_cast<uint8_t>(header_len_le32[2])) << 16;
            uint32_t header_b3 = static_cast<uint32_t>(static_cast<uint8_t>(header_len_le32[3])) << 24;
            uint32_t header_length = header_b0 | header_b1 | header_b2 | header_b3;
```

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xnpy --parallel 8
./build/test/test_xnpy
```

Expected: all `xnpy.*` tests pass (5 tests, including the new one).

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xnpy.hpp test/test_xnpy.cpp
git commit -m "fix: correctly parse NPY header length with high bit set (#2889)"
```

---

## Task 2: Fix CSV cell trim and 8-bit integer support (#2904)

**Files:**
- Modify: `include/xtensor/xcsv.hpp:69-70` and after `include/xtensor/xcsv.hpp:96`
- Test: `test/test_xcsv.cpp`

**Background:** Two independent bugs: (1) `lexical_cast<std::string>` computes `substr(first, last + 1)` — wrong when the cell has leading whitespace (the length must be `last - first + 1`); (2) there are no `lexical_cast` specializations for `signed char`/`unsigned char`, so `load_csv<uint8_t>` falls through to the generic `istringstream >>` path which reads a *character* instead of a number.

- [ ] **Step 1: Write the failing tests**

Append inside `namespace xt` in `test/test_xcsv.cpp` (the file includes `<sstream>`, `"xtensor/xcsv.hpp"`, `"xtensor/xtensor.hpp"` via `test_common` deps; if `xt::xtensor` is not in scope add `#include "xtensor/xtensor.hpp"`):

```cpp
    TEST(xcsv, load_binary_matrix)
    {
        const std::string source = "1,0,1\n"
                                   "0,1,1";

        std::stringstream source_stream(source);

        const xtensor<uint8_t, 2> res = load_csv<uint8_t>(source_stream);

        const xtensor<uint8_t, 2> exp{{1, 0, 1}, {0, 1, 1}};

        EXPECT_TRUE(all(equal(res, exp)));
    }

    TEST(xcsv, load_string_trims_cells)
    {
        const std::string source = "  alpha  , beta,gamma   \n delta,  epsilon , zeta  ";

        std::stringstream source_stream(source);

        const xtensor<std::string, 2> res = load_csv<std::string>(source_stream);

        EXPECT_EQ(res.shape()[0], std::size_t(2));
        EXPECT_EQ(res.shape()[1], std::size_t(3));
        EXPECT_EQ(res(0, 0), "alpha");
        EXPECT_EQ(res(0, 1), "beta");
        EXPECT_EQ(res(0, 2), "gamma");
        EXPECT_EQ(res(1, 0), "delta");
        EXPECT_EQ(res(1, 1), "epsilon");
        EXPECT_EQ(res(1, 2), "zeta");
    }
```

- [ ] **Step 2: Build and run to verify they fail**

```bash
cmake --build build --target xtest_xcsv --parallel 8
./build/test/test_xcsv -tc="xcsv.load_binary_matrix" -tc="xcsv.load_string_trims_cells"
```

Expected: `load_binary_matrix` FAILS (`CHECK_EQ(all(equal(res, exp)), true) is NOT correct`); `load_string_trims_cells` FAILS (values keep their surrounding whitespace).

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xcsv.hpp`, inside `detail::lexical_cast<std::string>` (line ~70), replace:

```cpp
            size_t last = cell.find_last_not_of(' ');
            return cell.substr(first, last == std::string::npos ? cell.size() : last + 1);
```

with:

```cpp
            size_t last = cell.find_last_not_of(' ');
            return cell.substr(first, last == std::string::npos ? cell.size() : last - first + 1);
```

Then after the `lexical_cast<int>` specialization (ends line ~96), insert two new specializations:

```cpp
        template <>
        inline signed char lexical_cast<signed char>(const std::string& cell)
        {
            return static_cast<signed char>(std::stoi(cell));
        }

        template <>
        inline unsigned char lexical_cast<unsigned char>(const std::string& cell)
        {
            return static_cast<unsigned char>(std::stoul(cell));
        }
```

- [ ] **Step 4: Build and run to verify they pass**

```bash
cmake --build build --target xtest_xcsv --parallel 8
./build/test/test_xcsv
```

Expected: all `xcsv.*` tests pass.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xcsv.hpp test/test_xcsv.cpp
git commit -m "fix: handle 8-bit integers and trim whitespace in CSV loading (#2904)"
```

---

## Task 3: Fix `clip` when `a_min > a_max` (#2909)

**Files:**
- Modify: `include/xtensor/xmath.hpp:606-613`
- Test: `test/test_xmath.cpp`

**Background:** `clip(v, lo, hi)` computed `lo <= v <= hi`; when `lo > hi` this returned garbage. NumPy semantics: the result must be `hi` everywhere when `lo > hi`. Two sites to change: the scalar path (`xtl::select`) and the SIMD path (`xt_simd::select`).

- [ ] **Step 1: Write the failing test**

Append inside `namespace xt` in `test/test_xmath.cpp` (after the existing `TEST(xmath, clip)` block, before `TEST(xmath, sign)`):

```cpp
    TEST(xmath, clip_amin_greater_than_amax)
    {
        // NumPy-compatible behavior: when a_min > a_max, all values
        // are set to a_max (the hi bound).
        const xarray<int> arr = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
        const xarray<int> expected = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
        EXPECT_EQ(expected, clip(arr, 8, 1));
    }
```

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xmath --parallel 8
./build/test/test_xmath -tc="xmath.clip_amin_greater_than_amax"
```

Expected: FAIL (`CHECK_EQ` not correct — values are not all 1).

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xmath.hpp`, inside the `clip` functor, replace:

```cpp
                return xtl::select(v < lo, lo, xtl::select(hi < v, hi, v));
```

with:

```cpp
                return xtl::select(lo < hi, xtl::select(v < lo, lo, xtl::select(hi < v, hi, v)), hi);
```

and replace the `simd_apply` variant:

```cpp
                return xt_simd::select(v < lo, lo, xt_simd::select(hi < v, hi, v));
```

with:

```cpp
                return xt_simd::select(lo < hi, xt_simd::select(v < lo, lo, xt_simd::select(hi < v, hi, v)), hi);
```

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xmath --parallel 8
./build/test/test_xmath
```

Expected: all `xmath.*` tests pass.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xmath.hpp test/test_xmath.cpp
git commit -m "fix: make clip return a_max when a_min > a_max (#2909)"
```

---

## Task 4: Give `poisson` and `geometric` a default `T = int` (#2917)

**Files:**
- Modify: `include/xtensor/xrandom.hpp` (4 declarations)
- Test: `test/test_xrandom.cpp`

**Background:** `random::poisson(shape, rate)` / `random::geometric(shape, prob)` have no argument from which the value type `T` can be deduced, so calling them without an explicit template argument is a compile error. Add `class T = int` defaults. The definitions (implementations) do NOT need changing — only the 4 `namespace random` declarations.

- [ ] **Step 1: Write the failing test**

Append inside `namespace xt` in `test/test_xrandom.cpp`:

```cpp
    TEST(xrandom, poisson_geometric_default_type)
    {
        // poisson and geometric have no parameter from which T can be deduced,
        // so they require a default T (= int) to be callable without explicit template arg.
        auto p = random::poisson({3, 3}, 1.0);
        static_assert(std::is_same<decltype(p)::value_type, int>::value, "poisson default T must be int");

        auto g = random::geometric({3, 3}, 0.5);
        static_assert(std::is_same<decltype(g)::value_type, int>::value, "geometric default T must be int");

        auto p2 = random::poisson({3, 3});
        static_assert(std::is_same<decltype(p2)::value_type, int>::value, "poisson default T must be int");
    }
```

- [ ] **Step 2: Build to verify it fails to compile (red = compile error)**

```bash
cmake --build build --target xtest_xrandom --parallel 8
```

Expected: COMPILE ERROR — `couldn't deduce template parameter 'T'` for `poisson`/`geometric`.

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xrandom.hpp` (in `namespace random`), apply these 4 declaration changes:

1. Line ~66:
```cpp
        template <class T, class S, class D = double, class E = random::default_engine_type>
        auto geometric(const S& shape, D prob = 0.5, E& engine = random::get_default_random_engine());
```
→ `template <class T = int, class S, class D = double, class E = random::default_engine_type>`

2. Line ~73:
```cpp
        template <class T, class S, class D = double, class E = random::default_engine_type>
        auto poisson(const S& shape, D rate = 1.0, E& engine = random::get_default_random_engine());
```
→ `template <class T = int, class S, class D = double, class E = random::default_engine_type>`

3. Line ~126:
```cpp
        template <class T, class I, std::size_t L, class D = double, class E = random::default_engine_type>
        auto geometric(const I (&shape)[L], D prob = 0.5, E& engine = random::get_default_random_engine());
```
→ `template <class T = int, class I, std::size_t L, class D = double, class E = random::default_engine_type>`

4. Line ~137:
```cpp
        template <class T, class I, std::size_t L, class D = double, class E = random::default_engine_type>
        auto poisson(const I (&shape)[L], D rate = 1.0, E& engine = random::get_default_random_engine());
```
→ `template <class T = int, class I, std::size_t L, class D = double, class E = random::default_engine_type>`

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xrandom --parallel 8
./build/test/test_xrandom -tc="xrandom.poisson_geometric_default_type"
```

Expected: builds, test PASSES.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xrandom.hpp test/test_xrandom.cpp
git commit -m "fix: add default T=int template parameter to poisson and geometric (#2917)"
```

---

## Task 5: Make `size()` conditionally noexcept (#2865)

**Files:**
- Modify: `include/xtensor/xaccessible.hpp:36` and `:141`

**Background:** `xconst_accessible<D>::size()` is declared `noexcept`, but it calls `derived_cast().shape()`, which may throw. A `noexcept` function that throws calls `std::terminate`. Make the `noexcept` conditional on the shape accessor. There is no behavior change and no regression test — verify by building.

- [ ] **Step 1: Apply the fix**

In `include/xtensor/xaccessible.hpp`, change the declaration (line ~36):

```cpp
        size_type size() const noexcept;
```

to:

```cpp
        size_type size() const noexcept(noexcept(derived_cast().shape()));
```

and the out-of-line definition (line ~141):

```cpp
    inline auto xconst_accessible<D>::size() const noexcept -> size_type
```

to:

```cpp
    inline auto xconst_accessible<D>::size() const noexcept(noexcept(derived_cast().shape())) -> size_type
```

- [ ] **Step 2: Build a broad test target to confirm nothing breaks**

```bash
cmake --build build --target xtest_xarray --parallel 8
./build/test/test_xarray
```

Expected: builds cleanly (no new warnings) and `xarray.*` tests pass. This exercises the whole container hierarchy that calls `size()`.

- [ ] **Step 3: Commit**

```bash
git add include/xtensor/xaccessible.hpp
git commit -m "fix: make size() conditionally noexcept to avoid std::terminate (#2865)"
```

---

## Task 6: Prevent buffer overflow on rank-mismatched fixed-dimension assignment (#2907)

**Files:**
- Modify: `include/xtensor/xcontainer.hpp:1000-1006`
- Test: `test/test_xassign.cpp`

**Background:** `xstrided_container<D>::resize` guarded the fixed-rank check with `XTENSOR_ASSERT_MSG`, which is a no-op in release builds. Assigning a higher-dimensional expression to `xtensor<T, N>` (e.g. `a = expand_dims(a, 0)` where `a` is `xtensor<float, 1>`) then copies N elements into a truncated buffer → stack/heap smash (the test below crashes with SIGABRT on unpatched code). Replace the assert with `XTENSOR_PRECONDITION`, which always throws `std::runtime_error`. The macro already exists in `include/xtensor/xexception.hpp`.

- [ ] **Step 1: Write the failing test**

Append inside `namespace xt` in `test/test_xassign.cpp` (after the last test, before the closing `}`). Add `#include "xtensor/xmanipulation.hpp"` to the file's include block (after line 16) so `expand_dims` is available:

```cpp
    TEST(xassign, fixed_dimension_mismatch)
    {
        auto a = xt::xtensor<float, 1>::from_shape({2});
        XT_ASSERT_THROW(a = xt::expand_dims(a, 0), std::runtime_error);
    }
```

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xassign --parallel 8
./build/test/test_xassign -tc="xassign.fixed_dimension_mismatch"
```

Expected: FAIL — the process CRASHES (SIGABRT, stack-smash detection). This is the bug itself; if it doesn't crash, the run must at least NOT pass.

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xcontainer.hpp`, inside `xstrided_container<D>::resize(S&& shape, bool force)` (line ~1003), replace:

```cpp
        XTENSOR_ASSERT_MSG(
            detail::check_resize_dimension(m_shape, shape),
            "cannot change the number of dimensions of xtensor"
        )
```

with:

```cpp
        XTENSOR_PRECONDITION(
            detail::check_resize_dimension(m_shape, shape),
            "cannot change the number of dimensions of xtensor"
        );
```

(Note the added trailing semicolon — the old macro call had none because the macro expands to a block.)

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xassign --parallel 8
./build/test/test_xassign
```

Expected: test PASSES (the assignment now throws deterministically in all build modes), and all other `xassign.*` tests still pass.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xcontainer.hpp test/test_xassign.cpp
git commit -m "fix: throw on rank-mismatched resize instead of overflowing buffer (#2907)"
```

---

## Task 7: Fix `xstepped_range` size underflow for empty ranges (#2927)

**Files:**
- Modify: `include/xtensor/xslice.hpp:1141-1142`
- Test: `test/test_xview.cpp`

**Background:** `xstepped_range` computed its element count as `n / step + (((n < 0) ^ (step > 0)) && (n % step))` with `size_type n = stop_val - start_val` (unsigned). For `range(3, 0, 1)`, `n` wraps to `2^64 - 3` → view shape `18446744073709551613`, then reads out of bounds. Fix: guard empty ranges first and compute the count with a plain remainder test.

- [ ] **Step 1: Write the failing tests**

In `test/test_xview.cpp`, insert before `TEST(xview, stored_range)` (line ~158):

```cpp
    TEST(xview, negative_step)
    {
        view_shape_type shape = {3, 4};
        xarray<double> a(shape);
        std::vector<double> data = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
        std::copy(data.cbegin(), data.cend(), a.template begin<layout_type::row_major>());

        auto view0 = view(a, 1, range(3, 0, -1));
        EXPECT_EQ(size_t(1), view0.dimension());
        EXPECT_EQ(size_t(3), view0.shape(0));
        EXPECT_EQ(a(1, 3), view0(0));
        EXPECT_EQ(a(1, 2), view0(1));
        EXPECT_EQ(a(1, 1), view0(2));
    }

    TEST(xview, size_zero)
    {
        view_shape_type shape = {3, 4};
        xarray<double> a(shape);
        std::vector<double> data = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
        std::copy(data.cbegin(), data.cend(), a.template begin<layout_type::row_major>());

        auto view0 = view(a, 1, range(0, 0));
        EXPECT_EQ(size_t(1), view0.dimension());
        EXPECT_EQ(size_t(0), view0.shape(0));

        auto view1 = view(a, 1, range(3, 0, 1));
        EXPECT_EQ(size_t(1), view1.dimension());
        EXPECT_EQ(size_t(0), view1.shape(0));

        auto view2 = view(a, 1, range(0, 3, -1));
        EXPECT_EQ(size_t(1), view2.dimension());
        EXPECT_EQ(size_t(0), view2.shape(0));
    }
```

(`view_shape_type`, `view`, `range` are already in scope in this file.)

- [ ] **Step 2: Build and run to verify they fail**

```bash
cmake --build build --target xtest_xview --parallel 8
./build/test/test_xview -tc="xview.size_zero"
```

Expected: FAIL — `CHECK_EQ(0, 18446744073709551613)` for `range(3, 0, 1)`.

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xslice.hpp`, inside `xstepped_range<T>::xstepped_range(size_type start_val, size_type stop_val, size_type step)` (lines ~1139-1143), replace:

```cpp
        size_type n = stop_val - start_val;
        m_size = n / step + (((n < 0) ^ (step > 0)) && (n % step));
```

with:

```cpp
        if ((step > 0 && start_val >= stop_val) || (step < 0 && start_val <= stop_val))
        {
            m_size = 0;
            return;
        }
        size_type n = stop_val - start_val;
        m_size = n / step + static_cast<bool>(n % step);
```

- [ ] **Step 4: Build and run to verify they pass**

```bash
cmake --build build --target xtest_xview --parallel 8
./build/test/test_xview -tc="xview.size_zero" -tc="xview.negative_step"
```

Expected: both PASS. Then run the whole file to confirm no view regressions.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xslice.hpp test/test_xview.cpp
git commit -m "fix: prevent xstepped_range size underflow for empty ranges (#2927)"
```

---

## Task 8: Fix `roll` negative-axis bounds handling (#2920)

**Files:**
- Modify: `include/xtensor/xmanipulation.hpp:1047-1063`
- Test: `test/test_xmanipulation.cpp`

**Background:** The 2-argument `roll(e, shift, axis)` cast `axis` to `std::size_t` before checking the bound, so a negative axis (e.g. `-1`) became a huge unsigned value and threw "axis is no within shape dimension" even though numpy supports negative axes. Fix uses `normalize_axis` (already present in `include/xtensor/xutils.hpp:362`).

- [ ] **Step 1: Write the failing test**

In `test/test_xmanipulation.cpp`, inside the existing `TEST(xmanipulation, roll)` block, after the line:

```cpp
        ASSERT_EQ(expected8, xt::roll(e2, -2, /*axis*/ 2));
```

append:

```cpp
        EXPECT_THROW(xt::roll(e2, 1, /*axis*/ 3), std::runtime_error);
        EXPECT_THROW(xt::roll(e2, 1, /*axis*/ -4), std::runtime_error);

        xarray<double> expected9 = {{{3, 1, 2}}, {{6, 4, 5}}, {{9, 7, 8}}};
        ASSERT_EQ(expected9, xt::roll(e2, -2, /*axis*/ -1));

        xarray<double> expected10 = {{{1, 2, 3}}, {{4, 5, 6}}, {{7, 8, 9}}};
        ASSERT_EQ(expected10, xt::roll(e2, -2, /*axis*/ -2));

        xarray<double> expected11 = {{{4, 5, 6}}, {{7, 8, 9}}, {{1, 2, 3}}};
        ASSERT_EQ(expected11, xt::roll(e2, 2, /*axis*/ -3));
```

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xmanipulation --parallel 8
./build/test/test_xmanipulation -tc="xmanipulation.roll"
```

Expected: FAIL — the negative-axis `ASSERT_EQ` cases throw `std::runtime_error` on current code.

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xmanipulation.hpp`, inside `roll(E&& e, std::ptrdiff_t shift, std::ptrdiff_t axis)` (lines ~1047-1062), replace:

```cpp
        auto cpy = empty_like(e);
        const auto& shape = cpy.shape();
        std::size_t saxis = static_cast<std::size_t>(axis);
        if (axis < 0)
        {
            axis += std::ptrdiff_t(cpy.dimension());
        }

        if (saxis >= cpy.dimension() || axis < 0)
        {
            XTENSOR_THROW(std::runtime_error, "axis is no within shape dimension.");
        }

        const auto axis_dim = static_cast<std::ptrdiff_t>(shape[saxis]);
```

with:

```cpp
        auto cpy = empty_like(e);
        const auto& shape = cpy.shape();
        const auto dim = cpy.dimension();

        if (axis < -static_cast<std::ptrdiff_t>(dim) || axis >= static_cast<std::ptrdiff_t>(dim))
        {
            XTENSOR_THROW(std::runtime_error, "axis is not within shape dimension.");
        }

        std::size_t saxis = normalize_axis(dim, axis);

        const auto axis_dim = static_cast<std::ptrdiff_t>(shape[saxis]);
```

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xmanipulation --parallel 8
./build/test/test_xmanipulation -tc="xmanipulation.roll"
```

Expected: the `roll` test PASSES (all 11 expected cases).

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xmanipulation.hpp test/test_xmanipulation.cpp
git commit -m "fix: handle negative and out-of-range axes in roll (#2920)"
```

---

## Task 9: Fix `roll` infinite loop / crash on zero-length dimensions (#2922)

**Files:**
- Modify: `include/xtensor/xmanipulation.hpp:952-963` and the axis overload from Task 8
- Test: `test/test_xmanipulation.cpp`

**Background:** `roll(e, shift)` computed `flat_size` by accumulating the shape (0 for an empty axis), then `shift %= flat_size` → division by zero (SIGFPE) or an infinite `while (shift < 0) shift += flat_size` loop when `flat_size == 0`. Early-return when the copy is empty. Do this after Task 8 (both touch the same function).

- [ ] **Step 1: Write the failing test**

In `test/test_xmanipulation.cpp`, inside `TEST(xmanipulation, roll)`, after the `expected11` line added in Task 8, append:

```cpp
        xarray<double> empty_1d = xt::xarray<double>::from_shape({0});
        EXPECT_EQ(xt::roll(empty_1d, 5).shape(), empty_1d.shape());

        xarray<double> partial_empty = xt::xarray<double>::from_shape({3, 0});
        EXPECT_EQ(xt::roll(partial_empty, 1, 1).shape(), partial_empty.shape());

        xarray<double> mixed_empty = xt::xarray<double>::from_shape({3, 0, 4});
        EXPECT_EQ(xt::roll(mixed_empty, 1, 0).shape(), mixed_empty.shape());
```

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xmanipulation --parallel 8
./build/test/test_xmanipulation -tc="xmanipulation.roll"
```

Expected: FAIL — division by zero (SIGFPE) or a hung/aborted run on `roll(empty_1d, 5)`.

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xmanipulation.hpp`, inside `roll(E&& e, std::ptrdiff_t shift)` (lines ~952-963), replace:

```cpp
        auto cpy = empty_like(e);
        auto flat_size = std::accumulate(
            cpy.shape().begin(),
            cpy.shape().end(),
            1L,
            std::multiplies<std::size_t>()
        );
        while (shift < 0)
```

with:

```cpp
        auto cpy = empty_like(e);

        if (cpy.size() == 0)
        {
            return cpy;
        }

        const auto flat_size = static_cast<std::ptrdiff_t>(cpy.size());
        while (shift < 0)
```

And inside `roll(E&& e, std::ptrdiff_t shift, std::ptrdiff_t axis)` (the body from Task 8), after the bounds-check `if` and before the `normalize_axis` line, insert:

```cpp
        if (cpy.size() == 0)
        {
            return cpy;
        }

```

(i.e. the final axis-overload body after Task 8 + Task 9 is:

```cpp
        auto cpy = empty_like(e);
        const auto& shape = cpy.shape();
        const auto dim = cpy.dimension();

        if (axis < -static_cast<std::ptrdiff_t>(dim) || axis >= static_cast<std::ptrdiff_t>(dim))
        {
            XTENSOR_THROW(std::runtime_error, "axis is not within shape dimension.");
        }

        if (cpy.size() == 0)
        {
            return cpy;
        }

        std::size_t saxis = normalize_axis(dim, axis);

        const auto axis_dim = static_cast<std::ptrdiff_t>(shape[saxis]);
        while (shift < 0)
        {
            shift += axis_dim;
        }

        detail::roll(cpy.begin(), e.begin(), shift, saxis, shape, 0);
        return cpy;
```

)

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xmanipulation --parallel 8
./build/test/test_xmanipulation -tc="xmanipulation.roll"
```

Expected: PASS — all roll assertions including the empty-array shape checks.

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xmanipulation.hpp test/test_xmanipulation.cpp
git commit -m "fix: handle zero-length dimensions in roll (#2922)"
```

---

## Task 10: Silence signed/unsigned warnings in `xbuilder` (no test) (#2926)

**Files:**
- Modify: `include/xtensor/xbuilder.hpp:502-580`

**Background:** Pure type-cleanliness fix: unqualified `size_t` and `std::accumulate` with a `1` initializer (deduced `int`) produce `-Wconversion` warnings. Replaces them with `std::size_t` and `size_t(1)`. No behavior change, no regression test — verify by building the xbuilder test under the CI warning flags.

- [ ] **Step 1: Apply the fix**

In `include/xtensor/xbuilder.hpp`, make these substitutions (the two `detail::concatenate_impl`/`stack_impl` helper lambdas):

1. Line ~502:
```cpp
                size_t axis_dim = *(first + axis + dim_offset);
```
→
```cpp
                std::size_t axis_dim = *(first + axis + dim_offset);
```

2. The `get` lambda of the concatenate helper (~line 516):
```cpp
                    size_t offset = 0;
                    const size_t end = arr.dimension();
                    for (size_t i = 0; i < end; i++)
```
→
```cpp
                    std::size_t offset = 0;
                    const std::size_t end = arr.dimension();
                    for (std::size_t i = 0; i < end; i++)
```

3. The `stride` accumulate in that lambda (~line 522):
```cpp
                        const size_t stride = std::accumulate(
                            shape.begin() + i + 1,
                            shape.end(),
                            1,
                            std::multiplies<size_t>()
                        );
```
→
```cpp
                        const std::size_t stride = std::accumulate(
                            shape.begin() + i + 1,
                            shape.end(),
                            size_t(1),
                            std::multiplies<std::size_t>()
                        );
```

4. The same two substitutions in the `stack_impl` `get_item` lambda (~line 565-580): `size_t offset` / `const size_t end` / `for (size_t i ...)` → `std::size_t` versions, and the `stride` accumulate initializer `size_t(1)` with `std::multiplies<std::size_t>()`.

- [ ] **Step 2: Build under the CI warning flags and confirm clean + green**

```bash
cmake -G Ninja -Bbuild-warn -DBUILD_TESTS=ON -DCMAKE_CXX_FLAGS="-Wall -Wextra -Wconversion -Wno-sign-conversion -Wold-style-cast -Wunused-variable" >/dev/null
cmake --build build-warn --target xtest_xbuilder --parallel 8 2>&1 | grep -iE "warning" | head
```

Expected: NO new `-Wconversion` warnings from `xbuilder.hpp` (pre-existing unrelated warnings may remain). Then run the test:

```bash
cmake --build build --target xtest_xbuilder --parallel 8
./build/test/test_xbuilder
```

Expected: `xbuilder.*` tests all pass (no behavior change).

- [ ] **Step 3: Commit**

```bash
git add include/xtensor/xbuilder.hpp
git commit -m "fix: silence signed/unsigned warnings in xbuilder helpers (#2926)"
```

---

## Task 11: Fix assignment through views with leading `newaxis()` slices (#2896)

**Files:**
- Modify: `include/xtensor/xview.hpp:1655-1659`
- Test: `test/test_xview.cpp`

**Background:** When a view starts with one or more `newaxis()` slices, `xview::index` computed the wrong slice index for writes, so assignments landed on the wrong element. The fix uses the helper `newaxis_skip` — this fork's `include/xtensor/xview_utils.hpp` already contains it (lines 276-280), so the backport is the one-liner from upstream.

- [ ] **Step 1: Write the failing test**

In `test/test_xview.cpp`, insert before `TEST(xview, in_bounds)` (line ~1465):

```cpp
    TEST(xview, assign_through_multiple_leading_newaxis)
    {
        SUBCASE("updates the underlying tensor for every element")
        {
            xt::xtensor<uint8_t, 2> tensor = xt::zeros<uint8_t>({4, 3});
            auto view = xt::view(tensor, xt::newaxis(), xt::newaxis(), xt::newaxis(), xt::all(), xt::all());

            uint8_t value = 0;
            for (std::size_t row = 0; row < 4; ++row)
            {
                for (std::size_t col = 0; col < 3; ++col)
                {
                    view(std::size_t{0}, std::size_t{0}, std::size_t{0}, row, col) = value;
                    EXPECT_EQ(tensor(row, col), value);
                    ++value;
                }
            }

            EXPECT_EQ(tensor, xt::arange<uint8_t>(12).reshape({4, 3}));
        }

        SUBCASE("preserves bool assignment semantics")
        {
            xt::xtensor<bool, 2> tensor = xt::zeros<bool>({4, 3});
            auto view = xt::view(tensor, xt::newaxis(), xt::newaxis(), xt::newaxis(), xt::all(), xt::all());

            for (std::size_t row = 0; row < 4; ++row)
            {
                for (std::size_t col = 0; col < 3; ++col)
                {
                    view(std::size_t{0}, std::size_t{0}, std::size_t{0}, row, col) = true;
                    EXPECT_TRUE(tensor(row, col));
                }
            }

            EXPECT_EQ(tensor, xt::ones<bool>({4, 3}));
        }
    }
```

- [ ] **Step 2: Build and run to verify it fails**

```bash
cmake --build build --target xtest_xview --parallel 8
./build/test/test_xview -tc="xview.assign_through_multiple_leading_newaxis"
```

Expected: FAIL — many `EXPECT_EQ`/`EXPECT_TRUE` mismatches (assignments land on wrong elements).

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xview.hpp`, inside `xview<CT, S...>::index<...>` for the `lesser_condition` branch (lines ~1655-1659), replace:

```cpp
        return sliced_access<I - integral_count_before<S...>(I) + newaxis_count_before<S...>(I + 1)>(
            std::get<I + newaxis_count_before<S...>(I + 1)>(m_slices),
            args...
        );
```

with:

```cpp
        constexpr size_type slice_index = newaxis_skip<S...>(I);
        return sliced_access<slice_index - integral_count_before<S...>(slice_index)>(
            std::get<slice_index>(m_slices),
            args...
        );
```

(`newaxis_skip` is already declared in `include/xtensor/xview_utils.hpp`, which `xview.hpp` includes; `size_type` is an `xview` member typedef.)

- [ ] **Step 4: Build and run to verify it passes**

```bash
cmake --build build --target xtest_xview --parallel 8
./build/test/test_xview
```

Expected: all `xview.*` tests pass (this is the biggest change surface; if any existing view test regresses, stop and report).

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xview.hpp test/test_xview.cpp
git commit -m "fix: correct index mapping for views with leading newaxis slices (#2896)"
```

---

## Task 12: Fix `xshared_expression` linear iterators (#2918)

**Files:**
- Modify: `include/xtensor/xexpression.hpp` (includes, type aliases, method block)
- Test: `test/test_xexpression.cpp`

**Background:** `xshared_expression<E>::linear_iterator` was `typename E::linear_iterator`, which fails to compile for expression types that don't expose that typedef (e.g. `xreducer`), so `make_xshared(sum(tensor, {2}))` broke. Fix: derive the iterator types from the free functions `xt::linear_begin`/`xt::linear_end` (already in this fork's `include/xtensor/xiterator.hpp:421,453`) and spell out the forwarding methods. Requires adding `#include "xiterator.hpp"` to `xexpression.hpp` — verified NOT to create a circular include (`xiterator.hpp` only includes `xexception.hpp` and `xlayout.hpp`).

- [ ] **Step 1: Write the failing test**

In `test/test_xexpression.cpp`:
- Add to the include block: `#include "xtensor/xtensor.hpp"` and `#include "xtensor/xrandom.hpp"`.
- Insert before `TEST(xexpression, temporary_type)`:

```cpp
    TEST(xexpression, shared_reducer_result)
    {
        std::size_t n = 1000;
        std::size_t m = 9;
        std::size_t o = 12;

        xtensor<double, 3> tensor = random::rand({n, m, o}, -20., 20.);
        auto result = make_xshared(sum(tensor, {2}));
        auto expected = sum(tensor, {2});

        EXPECT_EQ(result.dimension(), std::size_t(2));
        EXPECT_EQ(result.shape(), expected.shape());
        EXPECT_TRUE(all(equal(result, expected)));
    }
```

- [ ] **Step 2: Build to verify it fails to compile (red = compile error)**

```bash
cmake --build build --target xtest_xexpression --parallel 8
```

Expected: COMPILE ERROR — `class xt::xreducer<...> has no member named 'linear_begin'` (in the `XTENSOR_FORWARD_METHOD(linear_begin)` expansion).

- [ ] **Step 3: Apply the fix**

In `include/xtensor/xexpression.hpp`:

(a) Include block (lines ~13-16): add `<iterator>`:
```cpp
#include <cstddef>
#include <iterator>
#include <type_traits>
#include <vector>
```

(b) After the xtl includes (line ~21), add the fork's flat-path include:
```cpp
#include "xiterator.hpp"
```

(c) Replace the type aliases (lines ~538-540):
```cpp
        using linear_iterator = typename E::linear_iterator;
        using const_linear_iterator = typename E::const_linear_iterator;
```
with:
```cpp
        using linear_iterator = decltype(xt::linear_begin(std::declval<E&>()));
        using const_linear_iterator = decltype(xt::linear_begin(std::declval<const E&>()));
        using reverse_linear_iterator = std::reverse_iterator<linear_iterator>;
        using const_reverse_linear_iterator = std::reverse_iterator<const_linear_iterator>;
```

(d) Replace the twelve `XTENSOR_FORWARD_*_METHOD(linear_*)` lines (lines ~575-586) with explicit methods:
```cpp
        linear_iterator linear_begin() noexcept
        {
            return xt::linear_begin(*m_ptr);
        }

        linear_iterator linear_end() noexcept
        {
            return xt::linear_end(*m_ptr);
        }

        const_linear_iterator linear_begin() const noexcept
        {
            return xt::linear_begin(*m_ptr);
        }

        const_linear_iterator linear_end() const noexcept
        {
            return xt::linear_end(*m_ptr);
        }

        const_linear_iterator linear_cbegin() const noexcept
        {
            return xt::linear_begin(*m_ptr);
        }

        const_linear_iterator linear_cend() const noexcept
        {
            return xt::linear_end(*m_ptr);
        }

        reverse_linear_iterator linear_rbegin() noexcept
        {
            return reverse_linear_iterator(linear_end());
        }

        reverse_linear_iterator linear_rend() noexcept
        {
            return reverse_linear_iterator(linear_begin());
        }

        const_reverse_linear_iterator linear_rbegin() const noexcept
        {
            return const_reverse_linear_iterator(linear_end());
        }

        const_reverse_linear_iterator linear_rend() const noexcept
        {
            return const_reverse_linear_iterator(linear_begin());
        }

        const_reverse_linear_iterator linear_crbegin() const noexcept
        {
            return const_reverse_linear_iterator(linear_cend());
        }

        const_reverse_linear_iterator linear_crend() const noexcept
        {
            return const_reverse_linear_iterator(linear_cbegin());
        }
```

- [ ] **Step 4: Sanity-check no circular include, build, and run**

```bash
python3 tools/check_circular.py
cmake --build build --target xtest_xexpression --parallel 8
./build/test/test_xexpression
```

Expected: `check_circular.py` exits 0 (no cycle), build succeeds, all `xexpression.*` tests pass. Because `xexpression.hpp` is included nearly everywhere, also run the full aggregate build next:

```bash
cmake --build build --target test_xtensor_lib --parallel 8
```

Expected: the whole suite compiles (this is the real regression gate for this task).

- [ ] **Step 5: Commit**

```bash
git add include/xtensor/xexpression.hpp test/test_xexpression.cpp
git commit -m "fix: derive xshared_expression linear iterators via xt::linear_begin (#2918)"
```

---

## Final task: full verification

**Files:** none (verification only).

- [ ] **Step 1: Build and run the full suite**

```bash
cmake --build build --target test_xtensor_lib --parallel 8
ctest -R ^xtest$ --output-on-failure
```

Expected: all tests pass (the new tests plus the pre-existing suite, including the generated `test_extended_*` files and the `xsimd`/`xrandom`/`xview`/`xexpression` tests).

- [ ] **Step 2: Run a second build with the feature-flag matrix from CI** (at minimum the assert and no-exceptions configs, since Tasks 6 and 12 touch exception/precondition paths)

```bash
cmake -G Ninja -Bbuild-assert -DBUILD_TESTS=ON -DXTENSOR_ENABLE_ASSERT=ON
cmake --build build-assert --target test_xtensor_lib --parallel 8
./build-assert/test/test_xtensor_lib 2>&1 | tail -3

cmake -G Ninja -Bbuild-noexc -DBUILD_TESTS=ON -DXTENSOR_DISABLE_EXCEPTIONS=ON
cmake --build build-noexc --target test_xtensor_lib --parallel 8
./build-noexc/test/test_xtensor_lib 2>&1 | tail -3
```

Expected: both pass. (The CI matrix also covers `DEFAULT_COLUMN_MAJOR`, `XTENSOR_USE_XSIMD`, `XTENSOR_USE_OPENMP`, `XTENSOR_USE_TBB`, `CPP17`; run them if you have the deps installed.)

- [ ] **Step 3: Run pre-commit**

```bash
pre-commit run --all-files
```

Expected: clean. If clang-format reformats any edited header, commit the formatting changes.

- [ ] **Step 4: Final commit (if pre-commit changed anything)**

```bash
git add -u
git commit -m "style: apply clang-format to backported headers"
```

- [ ] **Step 5: Show the final diff**

```bash
git log --oneline origin/fork..HEAD
git diff origin/fork --stat
```

Expected: 12-13 commits (one per fix), touching only the listed headers + test files, no public-API or C++14-baseline changes.

---

## Self-review checklist (completed by plan author)

- **Spec coverage:** Every fix in the earlier "backportable" analysis is covered (Tasks 1-12). #2912, #2908, #2897, #2913 are excluded with documented reasons. ✔
- **Placeholder scan:** every task contains the full verbatim test code and the exact replacement code; verification commands include the expected outcome. ✔
- **Type consistency:** fix code was taken verbatim from the verified upstream commits (except Task 11 which is a verbatim one-liner using the already-present `newaxis_skip`, and Task 4 which is a template-default change); all line anchors were re-verified against this fork's files. ✔
- **Empirical verification:** the plan author compiled every task's test against (a) unmodified fork headers — confirming the red state for each (SIGABRT for #2907, SIGFPE for #2922, compile errors for #2917/#2918, wrong-value failures for the rest) — and (b) all fixes applied — confirming all 13 tests green, and a warning-clean build under `-Wall -Wextra -Wconversion`. ✔

# xtensor (fork)

> Fork 说明:本仓库是从 [xtensor](https://github.com/xtensor-stack/xtensor) fork 出来的维护分支,专注于在 **C++14 基线**上持续维护 `0.25.0` 版本。

## Fork 动机

上游 xtensor 从 `0.26.0` 起要求 C++17,从 `0.27.0` 起默认 C++20。对于仍停留在 C++14 工具链(较老的编译器、嵌入式/存量构建系统)的项目,无法直接升级使用新版本。

因此本 fork 固定于 `0.25.0` —— 最后一个完全支持 C++14 的版本,在保持其公共接口不变的前提下,持续接收上游的修复与改进。

## Fork 特性

- **C++14 基线**:所有公共头文件保持 C++14 兼容,不引入任何 C++17/20-only 特性(即便在 `CPP17`/`CPP20` 构建选项下,公共接口也不使用新标准特性);不整体合并上游 `>= 0.26` 的代码重组。
- **保持 0.25.0 公共接口**:`xarray`、`xtensor`、`xview`、`xreducer` 等公共 API 与 0.25.0 完全一致,仅按需回移独立修复。
- **持续回移上游修复**:从上游 `0.25.0` 之后的版本挑选与本分支兼容的 bug 修复,涵盖 NPY/CSV 读写、`roll`、切片与视图、随机数、迭代器、数值边界等。
- **本地数值修复**:修复了上游至今未修的问题,包括 `convolve` valid 模式的越界访问与混合类型编译错误、`interp` 空输入段错误与端点语义、`variance` 非法 `ddof` 的无符号下溢等;行为以 NumPy 为准。
- **健壮性与防御**:对空输入、非法参数等一律改为确定性抛异常(而非未定义行为);混合类型结果遵循 `std::common_type_t` 提升,避免截断。
- **质量保证**:每个修复均带回归测试;完整测试套件(78 个测试文件)在 `-Wextra -Wconversion` 等严格告警、assert 及 no-exceptions 构建下全部通过,并通过 CI 锁定的 clang-format 检查。

## 构建与测试

```bash
mamba env create -f environment-dev.yml
cmake -G Ninja -Bbuild -DBUILD_TESTS=ON
cmake --build build --target test_xtensor_lib --parallel 8
ctest -R ^xtest$ --output-on-failure
```

## 使用 FetchContent 集成

下游项目可用 CMake `FetchContent` 直接引入本 fork。xtl,以及在 `-DXTENSOR_USE_XSIMD=ON` 时的 xsimd,会由本 fork 的 CMake 自动获取(find_package 优先,找不到则 FetchContent),无需手动处理。

```cmake
include(FetchContent)

FetchContent_Declare(xtensor
    GIT_REPOSITORY https://github.com/JamzumSum/xtensor.git
    GIT_TAG        fork)          # 建议固定为具体 commit/tag 以保证可复现
FetchContent_MakeAvailable(xtensor)

# 线性代数(可选,需要系统 BLAS/LAPACK)
FetchContent_Declare(xtensor-blas
    GIT_REPOSITORY https://github.com/xtensor-stack/xtensor-blas.git
    GIT_TAG        0.21.0)
FetchContent_MakeAvailable(xtensor-blas)

target_link_libraries(myapp PRIVATE xtensor xtensor-blas)
```

说明:

- 启用 SIMD 时加 `-DXTENSOR_USE_XSIMD=ON`;xtl / xsimd 都会自动获取。
- 只需 xtensor(不含 linalg)时,省略 `xtensor-blas` 的 `FetchContent` 与最后的 `target_link_libraries`。
- `xtensor-blas` 需要系统 BLAS/LAPACK;也可用 `-DXTENSOR_USE_FLENS_BLAS=ON` 走纯头实现。
- `xtensor` 的 `GIT_TAG` 示例用分支 `fork`;生产构建建议固定到 commit SHA 或发布 tag。
- 缺依赖时本 fork 默认自动 FetchContent,可用 `-DXTENSOR_FETCH_DEPS=OFF` 禁用。

## 原 README

原始 README(库介绍、安装、使用示例、NumPy 对照表、性能等)请见 [README.old.md](README.old.md)。

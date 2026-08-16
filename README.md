# xtensor (fork)

> Fork 说明:本仓库是从 [xtensor](https://github.com/xtensor-stack/xtensor) fork 出来的维护分支,专注于在 **C++14 基线**上持续维护 `0.25.0` 版本。

## Fork 动机

上游 xtensor 从 `0.26.0` 起要求 C++17,从 `0.27.0` 起默认 C++20。对于仍停留在 C++14 工具链(较老的编译器、嵌入式/存量构建系统)的项目,无法直接升级使用新版本。

因此本 fork 固定于 `0.25.0` —— 最后一个完全支持 C++14 的版本,在保持其公共接口不变的前提下,持续接收上游的修复与改进。

## Fork 特性

- **C++14 基线**:所有公共头文件保持 C++14 兼容,不引入任何 C++17/20-only 特性(即便在 `CPP17`/`CPP20` 构建选项下,公共接口也不使用新标准特性)。
- **保持 0.25.0 公共接口**:`xarray`、`xtensor`、`xview`、`xreducer` 等公共 API 与 0.25.0 完全一致。
- **回移上游修复**:持续从上游 master(`0.25.0` 之后的提交)挑选与本分支兼容的 bug 修复与优化进行回移(见「更改情况」)。
- **不整体合并上游**:不合并上游 `>= 0.26` 的代码重组(C++17/20 化),仅按需回移独立修复。

## 更改情况

相对上游 `0.25.0` 发布点,本 fork 已回移以下上游修复,每个修复均带有回归测试:

| 上游 PR | 内容 |
|---|---|
| [#2889](https://github.com/xtensor-stack/xtensor/pull/2889) | 修复 NPY 文件头长度解析(signed char 符号扩展导致 >127 字节头误读) |
| [#2904](https://github.com/xtensor-stack/xtensor/pull/2904) | 修复 CSV 读取:单元格前导空白裁剪、`signed char`/`unsigned char` 支持 |
| [#2909](https://github.com/xtensor-stack/xtensor/pull/2909) | 修复 `clip` 在 `a_min > a_max` 时返回 `a_max`(NumPy 语义) |
| [#2917](https://github.com/xtensor-stack/xtensor/pull/2917) | `poisson` / `geometric` 增加默认模板参数 `T = int` |
| [#2865](https://github.com/xtensor-stack/xtensor/pull/2865) | `size()` 改为条件 `noexcept`,避免可抛异常时触发 `std::terminate` |
| [#2907](https://github.com/xtensor-stack/xtensor/pull/2907) | 修复固定维度容器秩不匹配赋值时的缓冲区溢出(改为确定性抛异常) |
| [#2927](https://github.com/xtensor-stack/xtensor/pull/2927) | 修复 `xstepped_range` 空区间尺寸下溢(shape 变为 `2^64-3` 的问题) |
| [#2920](https://github.com/xtensor-stack/xtensor/pull/2920) | `roll` 支持负轴并正确校验越界轴 |
| [#2922](https://github.com/xtensor-stack/xtensor/pull/2922) | `roll` 支持零长度维度(修复除零/死循环) |
| [#2926](https://github.com/xtensor-stack/xtensor/pull/2926) | `xbuilder` 符号/无符号类型警告清理 |
| [#2896](https://github.com/xtensor-stack/xtensor/pull/2896) | 修复带前置 `newaxis()` 切片的视图索引映射(赋值错位) |
| [#2918](https://github.com/xtensor-stack/xtensor/pull/2918) | 修复 `xshared_expression` 线性迭代器推导(`make_xshared(sum(...))` 无法编译) |

> 说明:`#2912`(`xt::drop` 传变量)经验证本分支已支持,无需回移;`#2908`、`#2897`、`#2913` 依赖上游 0.26 之后的重构(新头文件、std::apply 化等),暂不回移。

### 构建与测试

```bash
mamba env create -f environment-dev.yml
cmake -G Ninja -Bbuild -DBUILD_TESTS=ON
cmake --build build --target test_xtensor_lib --parallel 8
ctest -R ^xtest$ --output-on-failure
```

完整测试套件(78 个测试文件)在 `-Wextra -Wconversion` 等严格告警下全部通过。

## 原 README

原始 README(库介绍、安装、使用示例、NumPy 对照表、性能等)请见 [README.old.md](README.old.md)。

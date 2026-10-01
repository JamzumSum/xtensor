############################################################################
# Copyright (c) Johan Mabille, Sylvain Corlay and Wolf Vollprecht          #
# Copyright (c) QuantStack                                                 #
#                                                                          #
# Distributed under the terms of the BSD 3-Clause License.                 #
#                                                                          #
# The full license is in the file LICENSE, distributed with this software. #
############################################################################

# Resolve a dependency by first reusing an already-provided target, then
# find_package, and finally FetchContent (unless XTENSOR_FETCH_DEPS is OFF).
#
# Usage:
#   xtensor_find_or_fetch(<name> <version> <git_repository> <git_tag>)
function(xtensor_find_or_fetch name version repo tag)
    if(TARGET ${name})
        message(STATUS "${name} target already provided, reusing it")
        return()
    endif()

    find_package(${name} ${version} QUIET)
    if(${name}_FOUND)
        message(STATUS "Found ${name} v${${name}_VERSION}")
        return()
    endif()

    if(DEFINED XTENSOR_FETCH_DEPS AND NOT XTENSOR_FETCH_DEPS)
        message(FATAL_ERROR
            "${name} (>= ${version}) not found and XTENSOR_FETCH_DEPS=OFF. "
            "Install it or configure with -DXTENSOR_FETCH_DEPS=ON.")
    endif()

    message(STATUS "${name} not found, fetching ${repo} @ ${tag}")
    include(FetchContent)
    FetchContent_Declare(${name}
        GIT_REPOSITORY ${repo}
        GIT_TAG ${tag}
        GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(${name})
endfunction()

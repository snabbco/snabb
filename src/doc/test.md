# Testing

A very simple test framework is included.  Invoke it as `snabbswitch test [tests...]`, where the optional test specifications can be either Lua test files (without the `.lua` extension) or directories to be recursively walked, picking `*_t.lua` files.

Each should return a table of named test functions and subtables.  Test functions are tried if their names don't begin with a `_`.

If a table (or subtable) defines a `__setup()` function, it is executed before each function and subtable in the same table, but not each function in a subtable.  It receives four parameters: the table it's defined in, it's full name, the name of the function (or subtable) to be executed, and the function (or subtable) itself.

The test code should be straightforward, finishing the function (or the testfile) is considered a passed test, failing with `error()` or `assert()` signals test failure.  Any return value or error message is stored to be displayed in the final summary.

Example:

    return {
        sum = function ()
            assert(2+2 == 4, "if this fails, there's no hope")
        end,

        mult = function ()
            assert(2*2 == 4.1, "missed it by that much")
        end,

        strs = {
            concat = function ()
                assert('a'..'b' == 'ab', "the obvious thing")
            end,

            repeated = function ()
                assert(3*'a' == 'aaa', "would this work?")
            end,

            good_repeat = function ()
                assert(string.rep('a',3)=='aaa', "this should work")
            end,
        },
    }

output:

    ======= testsample_t
    [Ok]    testsample_t.sum
    [FAIL]  testsample_t.strs.repeated
    [Ok]    testsample_t.strs.concat
    [Ok]    testsample_t.strs.good_repeat
    [FAIL]  testsample_t.mult

    ======= 5 tests, 2 failures
    [FAIL]  testsample_t.strs.repeated:
    testsample_t.lua:17: attempt to perform arithmetic on a string value
    stack traceback:
            testsample_t.lua:17: in function <testsample_t.lua:16>
            [testsample_t.strs.repeated]
    ------
    [FAIL]  testsample_t.mult:
    testsample_t.lua:7: missed it by that much
    stack traceback:
            [C]: in function 'assert'
            testsample_t.lua:7: in function <testsample_t.lua:6>
            [testsample_t.mult]
    ------

note that there's no guaranteed order.  I see it as a feature.

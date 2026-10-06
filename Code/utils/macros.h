#pragma once

// list should look like: f(x) f(y) ...
#define APPLY(func, list) list(func)

// requires type to have type_init(void*, ...) -> type function
#define NEW(type, ...) (type##_init(malloc(sizeof(type)), ##__VA_ARGS__))

load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "consumer",
    srcs = ["consumer.go"],
    importpath = "example.com/analyzerfacts/consumer",
    visibility = ["//visibility:public"],
    deps = ["//test/analyzerfacts/relay"],
)

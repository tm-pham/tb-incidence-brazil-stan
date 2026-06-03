# Tests for the shared municipality-code helpers.

source(here::here("code", "02_data_processing", "geo_utils.R"))

test_that("normalise_muni6 reduces 7-digit codes and validates input", {
  expect_identical(normalise_muni6(c("3550308", "3304557")),
                   c(355030L, 330455L))
  expect_identical(normalise_muni6(c(355030L, 330455L)), c(355030L, 330455L))
  expect_error(normalise_muni6(c("3550308", NA)), "NA or empty")
  expect_error(normalise_muni6("12345"), "6 or 7 digits")
})

test_that("coalesce_muni_code prefers residence and falls back to occurrence", {
  out <- coalesce_muni_code(c("355030", "", NA, "999999"),
                            c("330455", "330455", "330455", "330455"))
  expect_equal(as.vector(out), c("355030", "330455", "330455", "330455"))
  # Three of four rows took the fallback; surfaced as an attribute.
  expect_equal(attr(out, "n_fallback"), 3L)
  expect_equal(attr(out, "n_total"), 4L)
})

test_that("coalesce_muni_code errors when both codes are invalid", {
  expect_error(coalesce_muni_code(c(NA, "999999"), c("999999", NA)),
               "neither a valid residence")
})

test_that("coalesce_muni_code errors on unequal-length inputs", {
  expect_error(coalesce_muni_code(c("355030"), c("355030", "330455")),
               "equal length")
})

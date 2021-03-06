context("Bundle")

withTestContext({

  test_that("Bundle works when using R's internal tar", {

    skip_on_cran()

    TAR <- Sys.getenv("TAR")
    Sys.setenv(TAR = "")
    on.exit(Sys.setenv(TAR = TAR), add = TRUE)

    owd <- getwd()
    setwd(tempdir())
    on.exit(setwd(owd), add = TRUE)

    dir.create("packrat-test-bundle")
    setwd("packrat-test-bundle")
    packrat::init(enter = FALSE)
    packrat::bundle(file = "test-bundle.tar.gz")
    untar("test-bundle.tar.gz", exdir = "untarred")
    expect_identical(
      grep("lib*", list.files("packrat"), value = TRUE, invert = TRUE),
      list.files("untarred/packrat-test-bundle/packrat/")
    )

    unlink(file.path(tempdir(), "packrat-test-bundle"), recursive = TRUE)

  })

  test_that("Bundle works when using an external tar", {

    skip_on_cran()

    if (Sys.getenv("TAR") != "") {

      owd <- getwd()
      setwd(tempdir())

      dir.create("packrat-test-bundle")
      setwd("packrat-test-bundle")
      cat("library(bread)", file = "test.R")
      packrat::init(enter = FALSE)
      packrat::bundle(file = file.path("test-bundle.tar.gz"))
      untar("test-bundle.tar.gz", exdir = "untarred")
      expect_identical(
        grep("lib*", list.files("packrat"), value = TRUE, invert = TRUE),
        list.files("untarred/packrat-test-bundle/packrat/")
      )

      unlink(file.path(tempdir(), "packrat-test-bundle"), recursive = TRUE)
      setwd(owd)

    }

  })

  test_that("Bundle works when omitting CRAN packages", {

    skip_on_cran()

    if (Sys.getenv("TAR") != "") {

      owd <- getwd()
      setwd(tempdir())

      dir.create("packrat-test-bundle")
      setwd("packrat-test-bundle")
      cat("library(bread)", file = "test.R")
      packrat::init(enter = FALSE)
      packrat::bundle(file = file.path("test-bundle.tar.gz"), omit.cran.src = TRUE)
      untar("test-bundle.tar.gz", exdir = "untarred")
      expect_identical(
        setdiff(
          grep("lib*", list.files("packrat"), value = TRUE, invert = TRUE),
          "src"
        ),
        list.files("untarred/packrat-test-bundle/packrat/")
      )

      unlink(file.path(tempdir(), "packrat-test-bundle"), recursive = TRUE)
      setwd(owd)

    }

    ## Test for internal TAR
    owd <- getwd()
    setwd(tempdir())

    if (file.exists("packrat-test-bundle"))
      unlink("packrat-test-bundle", recursive = TRUE)

    dir.create("packrat-test-bundle")
    setwd("packrat-test-bundle")
    cat("library(bread)", file = "test.R")
    packrat::init(enter = FALSE)
    packrat:::bundle_internal(file = file.path("test-bundle.tar.gz"), omit.cran.src = TRUE)
    untar("test-bundle.tar.gz", exdir = "untarred")
    expect_identical(
      grep("lib*", list.files("packrat"), value = TRUE, invert = TRUE),
      list.files("untarred/packrat-test-bundle/packrat/")
    )

    unlink(file.path(tempdir(), "packrat-test-bundle"), recursive = TRUE)
    setwd(owd)

  })

})

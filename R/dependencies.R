#' Detect Application Dependencies
#'
#' Recursively detect all package dependencies for an application. This function
#' parses all \R files in the application directory to determine what packages
#' the application depends directly.
#'
#' Only direct dependencies are detected (i.e. no recursion is done to find the
#' dependencies of the dependencies).
#'
#' @param project Directory containing application. Defaults to current working
#'   directory.
#' @param implicit.packrat.dependency Include \code{packrat} as an implicit
#'   dependency of this project, if not otherwise discovered? This should be
#'   \code{FALSE} only if you can guarantee that \code{packrat} will be available
#'   via other means when attempting to load this project.
#'
#' @details Dependencies are determined by parsing application source code and
#'   looking for calls to \code{library}, \code{require}, \code{::}, and
#'   \code{:::}.
#'
#' @return Returns a list of the names of the packages on which R code in the
#'   application depends.
#'
#' @examples
#'
#' \dontrun{
#'
#' # dependencies for the app in the current working dir
#' appDependencies()
#'
#' # dependencies for an app in another directory
#' appDependencies("~/projects/shiny/app1")
#'
#' }
#' @keywords internal
appDependencies <- function(project = NULL,
                            available.packages = NULL,
                            fields = c("Imports", "Depends", "LinkingTo"),
                            implicit.packrat.dependency = TRUE) {

  if (is.null(available.packages)) available.packages <- available.packages()

  project <- getProjectDir(project)

  ## We want to search both local and global library paths for DESCRIPTION files
  ## in the recursive dependency lookup; hence we take a large (ordered) union
  ## of library paths. The ordering ensures that we search the private library first,
  ## and fall back to the local / global library (necessary for `packrat::init`)
  libPaths <- c(
    libDir(project),
    .libPaths(),
    .packrat_mutables$origLibPaths
  )

  ## For R packages, we only use the DESCRIPTION file
  if (isRPackage(project)) {

    ## Make sure we get records recursively from the packages in DESCRIPTION
    parentDeps <-
      pkgDescriptionDependencies(file.path(project, "DESCRIPTION"))$Package

    # Strip out any dependencies the user has requested we do not track.
    parentDeps <- setdiff(parentDeps, packrat::opts$ignored.packages())

    ## For downstream dependencies, we don't grab their Suggests:
    ## Presumedly, we can build child dependencies without vignettes, and hence
    ## do not need suggests -- for the package itself, we should make sure
    ## we grab suggests, however
    childDeps <- recursivePackageDependencies(parentDeps,
                                              libPaths,
                                              available.packages,
                                              fields)
  } else {
    parentDeps <- setdiff(unique(c(dirDependencies(project))), "packrat")
    parentDeps <- setdiff(parentDeps, packrat::opts$ignored.packages())
    childDeps <- recursivePackageDependencies(parentDeps,
                                              libPaths,
                                              available.packages,
                                              fields)
  }

  result <- unique(c(parentDeps, childDeps))

  # should packrat be included as automatic dependency?
  if (implicit.packrat.dependency) {
    result <- unique(c(result, "packrat"))
  }

  # If this project is implicitly a shiny application, then
  # add that in as the previously run expression dependency lookup
  # won't have found it.
  if (!("shiny" %in% result) && isShinyApp(project))
    result <- c(result, "shiny")

  sort_c(result)
}

# detect all package dependencies for a directory of files
dirDependencies <- function(dir) {
  dir <- normalizePath(dir, winslash='/')

  # first get the packages referred to in source code
  pattern <- "\\.[rR]$|\\.[rR]md$|\\.[rR]nw$|\\.[rR]pres$"
  pkgs <- character()
  R_files <- list.files(dir,
                        pattern = pattern,
                        ignore.case = TRUE,
                        recursive = TRUE
  )

  ## Avoid anything within the packrat directory itself -- all inference
  ## should be done on user code
  packratDirRegex <- paste("^", .packrat$packratFolderName, sep = "")
  R_files <- grep(packratDirRegex, R_files, invert = TRUE, value = TRUE)


  sapply(R_files, function(file) {
    filePath <- file.path(dir, file)
    pkgs <<- append(pkgs, fileDependencies(file.path(dir, file)))

  })

  ## Exclude recommended packages if there is no package installed locally
  ## this places an implicit dependency on the system-installed version of a package
  dropSystemPackages(pkgs)

}

# detect all package dependencies for a source file (parses the file and then
# recursively examines all expressions in the file)

# ad-hoc dispatch based on the file extension
fileDependencies <- function(file) {
  fileext <- tolower(gsub(".*\\.", "", file))
  switch (fileext,
          r = fileDependencies.R(file),
          rmd = fileDependencies.Rmd(file),
          rnw = fileDependencies.Rnw(file),
          rpres = fileDependencies.Rpres(file),
          stop("Unrecognized file type '", file, "'")
  )
}

hasYamlFrontMatter <- function(content) {
  lines <- grep("^(---|\\.\\.\\.)\\s*$", content, perl = TRUE)
  1 %in% lines && length(lines) >= 2 && grepl("^---\\s*$", content[1], perl=TRUE)
}

yamlDeps <- function(yaml) {
  c(
    "shiny"[any(grepl("runtime:[[:space:]]*shiny", yaml, perl = TRUE))],
    "rticles"[any(grepl("rticles::", yaml, perl = TRUE))]
  )
}

fileDependencies.Rmd <- function(file) {

  deps <- "rmarkdown"

  # We need to check for and parse YAML frontmatter if necessary
  yamlDeps <- NULL
  content <- readLines(file)
  if (hasYamlFrontMatter(content)) {

    # Extract the YAML frontmatter.
    tripleDashesDots <- grep("^(---|\\.\\.\\.)\\s*$", content, perl = TRUE)
    start <- tripleDashesDots[[1]]
    end <- tripleDashesDots[[2]]
    yaml <- paste(content[(start + 1):(end - 1)], collapse = "\n")

    # Populate 'deps'.
    yamlDeps <- yamlDeps(yaml)
    deps <- c(deps, yamlDeps)

    # Extract additional dependencies from YAML parameters.
    if (requireNamespace("knitr", quietly = TRUE) &&
        packageVersion("knitr") >= "1.10.18") {

      knitParams <- knitr::knit_params_yaml(yaml, evaluate = FALSE)
      if (length(knitParams) > 0) {
        deps <- c(deps, "shiny")
        for (param in knitParams) {
          if (!is.null(param$expr)) {
            parsed <- tryCatch(
              parse(text = param$expr),
              error = function(e) NULL
            )

            if (length(parsed))
              deps <- c(deps, expressionDependencies(parsed))
          }
        }
      }

    }
  }


  # Escape hatch for empty .Rmd files
  if (!length(content) || identical(unique(gsub("[[:space:]]", "", content, perl = TRUE)), "")) {
    return(deps)
  }

  ## Unload knitr if needed only for the duration of this function call
  ## This prevents errors with e.g. `packrat::restore` performed after
  ## a `fileDependencies.Rmd` call on Windows, where having knitr loaded
  ## would prevent an installation of knitr to succeed
  knitrIsLoaded <- "knitr" %in% loadedNamespaces()
  on.exit({
    if (!knitrIsLoaded && "knitr" %in% loadedNamespaces()) {
      try(unloadNamespace("knitr"), silent = TRUE)
    }
  })

  if (requireNamespace("knitr", quietly = TRUE)) {
    tempfile <- tempfile()
    on.exit(unlink(tempfile))
    tryCatch(silent(
      knitr::knit(file, output = tempfile, tangle = TRUE)
    ), error = function(e) {
      message("Unable to tangle file '", file, "'; cannot parse dependencies")
      character()
    })
    c(deps, fileDependencies.R(tempfile))
  } else {
    warning("knitr is required to parse dependencies but is not available")
    deps
  }
}

fileDependencies.knitr <- function(...) {
  fileDependencies.Rmd(...)
}

fileDependencies.Rpres <- function(...) {
  fileDependencies.Rmd(...)
}

fileDependencies.Rnw <- function(file) {
  tempfile <- tempfile()
  on.exit(unlink(tempfile))
  tryCatch(silent({
    utils::Stangle(file, output = tempfile)
    fileDependencies.R(tempfile)
  }), error = function(e) {
    fileDependencies.knitr(file)
  })
}

fileDependencies.R <- function(file) {

  if (!file.exists(file)) {
    warning("No file at path '", file, "'.")
    return(character())
  }

  # build a list of package dependencies to return
  pkgs <- character()

  # parse file and examine expressions
  tryCatch({
    # parse() generates a warning when the file has an incomplete last line, but
    # it still parses the file correctly; ignore this and other warnings.
    # We'll still halt when parsing fails.
    exprs <- suppressWarnings(parse(file, n = -1L))
    for (i in seq_along(exprs))
      pkgs <- append(pkgs, expressionDependencies(exprs[[i]]))
  }, error = function(e) {
    warning(paste("Failed to parse", file, "; dependencies in this file will",
                  "not be discovered."))
  })

  # return packages
  unique(pkgs)
}

anyOf <- function(object, ...) {
  predicates <- list(...)
  for (predicate in predicates)
    if (predicate(object))
      return(TRUE)
  FALSE
}

allOf <- function(object, ...) {
  predicates <- list(...)
  for (predicate in predicates)
    if (!predicate(object))
      return(FALSE)
  TRUE
}

recursiveWalk <- function(`_node`, fn, ...) {
  fn(`_node`, ...)
  if (is.call(`_node`)) {
    for (i in seq_along(`_node`)) {
      recursiveWalk(`_node`[[i]], fn, ...)
    }
  }
}

# Fills 'env' as a side effect
identifyPackagesUsed <- function(call, env) {

  if (!is.call(call))
    return()

  fn <- call[[1]]
  if (!anyOf(fn, is.character, is.symbol))
    return()

  fnString <- as.character(fn)

  # Check for '::', ':::'
  if (fnString %in% c("::", ":::")) {
    if (anyOf(call[[2]], is.character, is.symbol)) {
      pkg <- as.character(call[[2]])
      env[[pkg]] <- TRUE
      return()
    }
  }

  # Check for S4-related function calls (implying a dependency on methods)
  if (fnString %in% c("setClass", "setMethod", "setRefClass", "setGeneric", "setGroupGeneric")) {
    env[["methods"]] <- TRUE
    return()
  }

  # Check for packge loaders
  pkgLoaders <- c("library", "require", "loadNamespace", "requireNamespace")
  if (!fnString %in% pkgLoaders)
    return()

  # Try matching the call.
  loader <- tryCatch(
    get(fnString, envir = asNamespace("base")),
    error = function(e) NULL
  )

  if (!is.function(loader))
    return()

  matched <- match.call(loader, call)
  if (!"package" %in% names(matched))
    return()

  # Protect against 'character.only = TRUE' + symbols.
  # This defends us against a construct like:
  #
  #    for (x in pkgs)
  #        library(x, character.only = TRUE)
  #
  if ("character.only" %in% names(matched)) {
    if (is.symbol(matched[["package"]])) {
      return()
    }
  }

  if (anyOf(matched[["package"]], is.symbol, is.character)) {
    pkg <- as.character(matched[["package"]])
    env[[pkg]] <- TRUE
    return()
  }


}

expressionDependencies <- function(e) {

  if (is.expression(e)) {
    return(unlist(lapply(e, function(call) {
      expressionDependencies(call)
    })))
  }

  else if (is.call(e)) {
    env <- new.env(parent = emptyenv())
    recursiveWalk(e, identifyPackagesUsed, env)
    return(ls(env, all.names = TRUE))
  }

  else character()

}

# Read a DESCRIPTION file into a data.frame
readDESCRIPTION <- function(path) {

  if (!file.exists(path))
    stop("No DESCRIPTION file at path '", path, "'")

  tryCatch(
    readDcf(file = path, all = TRUE),
    error = function(e) {
      return(data.frame())
    }
  )
}

isRPackage <- function(project) {

  descriptionPath <- file.path(project, "DESCRIPTION")
  if (!file.exists(descriptionPath))
    return(FALSE)

  DESCRIPTION <- readDESCRIPTION(descriptionPath)

  # If 'Type' is missing from the DESCRIPTION file, then we implicitly assume
  # that it is an R package (#172)
  if (!("Type" %in% names(DESCRIPTION)))
    return(TRUE)

  # Otherwise, ensure that the type is `Package`
  Type <- unname(as.character(DESCRIPTION$Type))
  identical(Type, "Package")

}

# Infer whether a project is (implicitly) a Shiny application,
# in the absence of explicit `library()` statements.
isShinyApp <- function(project) {

  # Check for a DESCRIPTION file with 'Type: Shiny'
  descriptionPath <- file.path(project, "DESCRIPTION")
  if (file.exists(descriptionPath)) {
    DESCRIPTION <- readDESCRIPTION(descriptionPath)
    if (length(DESCRIPTION$Type) && tolower(DESCRIPTION$Type) == "shiny")
      return(TRUE)
  }

  # Check for a server.r with a 'shinyServer' call
  serverPath <- file.path(project, "server.R")
  if (file.exists(file.path(project, "server.R"))) {
    contents <- paste(readLines(serverPath), collapse = "\n")
    if (grepl("shinyServer\\s*\\(", contents, perl = TRUE))
      return(TRUE)
  }

  # Check for a single-file application with 'app.R'
  appPath <- file.path(project, "app.R")
  if (file.exists(appPath)) {
    contents <- paste(readLines(appPath), collapse = "\n")
    if (grepl("shinyApp\\s*\\(", contents, perl = TRUE))
      return(TRUE)
  }

  return(FALSE)
}

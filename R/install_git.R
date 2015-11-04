#' Install a package from git
#'
#' Use the \code{\link[devtools:install_git]{devtools::install_git}}
#' function to install packages into a project private library. Using this
#' function rather than calling devtools directly enables you to install git
#' packages without adding devtools and it's dependencies to your project
#' private library.
#'
#' @param url Location of package. The url should point to a public or
#'   private repository.
#' @param branch Name of branch or tag to use, if not master.
#' @param subdir A sub-directory within a git repository that may
#'   contain the package we are interested in installing.
#' @param args DEPRECATED. A character vector providing extra arguments to
#'   pass on to git.
#' @param ... passed on to \code{\link{install}}
#' @export
#' @family package installation
#' @examples
#' \dontrun{
#' install_git("git://github.com/hadley/stringr.git")
#' install_git("git://github.com/hadley/stringr.git", branch = "stringr-0.2")
#' @param dependencies \code{NA} (the default) has the same behavior as
#'   \code{install.packages} (installs "Depends", "Imports", and "LinkingTo").
#'   See the documentation for
#'   \code{\link[utils:install.packages]{install.packages}} for details on other
#'   valid arguments.
#'
#' @note This function requires the \pkg{devtools} package and will prompt to
#' to install it if it's not already available in the standard library paths.
#' In this case, devtools will be installed into the standard user package
#' library rather than the project private library.
#'
#' @export
install_github <-function(url, subdir = NULL, branch = NULL, args = character(0),
                          ...) {
  # look for devtools in the original libs and prompt to install if necessary
  origLibPaths <- .packrat_mutables$get("origLibPaths")
  if (length(find.package("devtools", lib.loc = origLibPaths, quiet = TRUE)) == 0) {
    if (interactive()) {
      message("Installing packages from git requires the devtools package.")
      response <- readline("Do you want to install devtools now? [Y/n]: ")
      if (substr(tolower(response), 1, 1) != "n")
        utils::install.packages("devtools", lib = origLibPaths)
    } else {
      stop("packrat::install_git requires the devtools package.")
    }
  }

  # execute devtools::install_git with version of devtools (and dependencies)
  # installed in original lib paths
  args <- list(...)
  args$url <- url
  args$subdir <- subdir
  args$branch <- branch
  with_extlib(c("httr", "devtools"), envir = environment(), {
    f <- get("install_git", envir = as.environment("package:devtools"))
    do.call(f, args)
  })
  invisible()
}



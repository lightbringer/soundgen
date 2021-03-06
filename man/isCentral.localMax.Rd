% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utilities_analyze.R
\name{isCentral.localMax}
\alias{isCentral.localMax}
\title{Simple peak detection}
\usage{
isCentral.localMax(x, threshold)
}
\arguments{
\item{x}{input vector}

\item{threshold}{threshold for peak detection}
}
\description{
Internal soundgen function.
}
\details{
Peak detection with \code{\link[zoo]{rollapply}}. Less versatile but x 10
faster than \code{\link[seewave]{fpeaks}}.
}

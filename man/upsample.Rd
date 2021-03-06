% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utilities_soundgen.R
\name{upsample}
\alias{upsample}
\title{Upsample pitch contour}
\usage{
upsample(pitch_per_gc, samplingRate = 44100)
}
\arguments{
\item{pitch_per_gc}{a vector of fundamental frequencies per glottal cycle}

\item{samplingRate}{target sampling rate after upsampling, in Hz}
}
\value{
Returns a list of two vectors: pitch_upsampled (the upsampled version
  of the input) and gc_upsampled (new indices of glottal cycles on an
  upsampled scale)
}
\description{
Internal soundgen function.
}
\details{
Upsamples a pitch contour to samplingRate through linear interpolation
between successive glottal cycles.
}
\examples{
soundgen:::upsample(c(100, 150, 130), samplingRate = 16000)
}

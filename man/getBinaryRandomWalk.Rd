% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utilities_math.R
\name{getBinaryRandomWalk}
\alias{getBinaryRandomWalk}
\title{Discrete random walk}
\usage{
getBinaryRandomWalk(rw, noiseAmount = 50, minLength = 50)
}
\arguments{
\item{rw}{a random walk generated by \code{\link{getRandomWalk}} (expected
range 0 to 100)}

\item{minLength}{the mimimum length of each epoch}

\item{noise_amount}{a number between 0 to 100: 0 = returns all zeroes; 100 =
returns all twos}
}
\value{
Returns a vector of integers (0/1/2) of the same length as rw.
}
\description{
Internal soudgen function.
}
\details{
Takes a continuous random walk and converts it to continuous epochs of
repeated values 0/1/2, each at least minLength points long. 0/1/2 correspond
to different noise regimes: 0 = no noise, 1 = subharmonics, 2 = subharmonics
and jitter/shimmer.
}
\examples{
rw = soundgen:::getRandomWalk(len = 100, rw_range = 100, rw_smoothing = .2)
plot (rw, type = 'l')
plot (soundgen:::getBinaryRandomWalk(rw, noiseAmount = 75, minLength = 10))
plot (soundgen:::getBinaryRandomWalk(rw, noiseAmount = 5, minLength = 10))
}
\keyword{internal}

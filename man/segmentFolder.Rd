% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/segment.R
\name{segmentFolder}
\alias{segmentFolder}
\title{Segment all files in a folder}
\usage{
segmentFolder(myfolder, shortest_syl = 40, shortest_pause = 40,
  syl_to_global_mean = 0.9, interburst_min_ms = NULL,
  interburst_min_scale = 1, peak_to_global_max = 0.075,
  peak_to_trough = 3, trough_left = TRUE, trough_right = FALSE,
  smooth_ms = 40, smooth_overlap = 80, summary = TRUE, plot = FALSE,
  savePath = NA, verbose = TRUE, ...)
}
\arguments{
\item{myfolder}{full path to target folder}

\item{shortest_syl}{minimum acceptable length of syllables (ms)}

\item{shortest_pause}{minimum acceptable break between syllables (ms).
Syllables separated by less time are merged. To avoid merging, specify
\code{shortest_pause = NA}}

\item{syl_to_global_mean}{amplitude threshold for syllable detection (as a
proportion of global mean amplitude of smoothed envelope)}

\item{interburst_min_ms}{minimum time between two consecutive bursts (ms). If
specified, it overrides \code{interburst_min_idx}}

\item{interburst_min_scale}{multiplier of the default minimum interburst
interval (median syllable length or, if no syllables are detected, the same
number as \code{shortest_syl}). Only used if \code{interburst_min_ms} is
not specified. Larger values improve detection of unusually broad shallow
peaks, while smaller values improve the detection of sharp narrow peaks}

\item{peak_to_global_max}{to qualify as a burst, a local maximum has to be at
least \code{peak_to_global_max} time the height of the global maximum of
the entire amplitude envelope}

\item{peak_to_trough}{to qualify as a burst, a local maximum has to be at
least \code{peak_to_trough}  times the local minimum on the LEFT over
analysis window (which is controlled by \code{interburst_min_ms} or
\code{interburst_min_scale})}

\item{trough_left}{should local maxima be compared to the trough
on the left and/or right of it? TRUE / FALSE}

\item{trough_right}{should local maxima be compared to the trough
on the left and/or right of it? TRUE / FALSE}

\item{smooth_ms}{length of smoothing window (ms). Capped at half the length
of sound. Low values dramatically increase processing time}

\item{smooth_overlap}{overlap between smoothing windows (%): the higher, the
more accurate, but also slower}

\item{summary}{if TRUE, returns only a summary of the number and spacing of
syllables and vocal bursts. If FALSE, returns a list containing full stats
on each syllable and bursts (location, duration, amplitude, ...)}

\item{plot}{should a segmentation plot be plotted? TRUE / FALSE}

\item{savePath}{full path to the folder in which to save the plots. If you
don't want to save the plots, set \code{savePath} to NA (default)}

\item{verbose}{If TRUE, reports progress and estimated time left}

\item{...}{other graphical parameters}
}
\value{
If \code{summary} is TRUE, returns a dataframe with one row per audio
  file. If \code{summary} is FALSE, returns a list of detailed descriptives.
}
\description{
Finds syllables and bursts in all .wav files in a folder.
}
\details{
This is just a convenient wrapper for \code{\link{segment}} intended for
analyzing the syllables and bursts in a large number of audio files at a
time. In verbose mode, it also reports ETA every ten iterations. With default
settings, running time should be about a second per minute of audio.
}
\examples{
\dontrun{
# download 260 sounds from Anikin & Persson (2017)
# http://cogsci.se/personal/results/
# 01_anikin-persson_2016_naturalistics-non-linguistic-vocalizations/260sounds_wav.zip
# unzip them into a folder, say '~/Downloads/temp'
myfolder = '~/Downloads/temp'  # 260 .wav files live here
s = segmentFolder(myfolder, verbose = TRUE)

# import manual counts of syllables in 260 sounds from Anikin & Persson (2017) (our "key")
key = segment_manual  # a vector of 260 integers
trial = as.numeric(s$nBursts)
cor (key, trial, use = 'pairwise.complete.obs')
boxplot(trial ~ as.integer(key), xlab='key')
abline(a=0, b=1, col='red')
}
}

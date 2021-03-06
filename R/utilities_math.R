### UTILITIES FOR LOW-LEVEL MATH ###

#' Convert Hz to semitones
#'
#' Internal soundgen function.
#'
#' Converts from Hz to semitones above C0 (~16.4 Hz).
#' @param h vector of frequencies (Hz)
### UTILITIES for soundgen::generateBout() ###
HzToSemitones = function(h) {
  out = sapply(h, function(x)
    log2(x / 16.3516) * 12)
  # this is also the index of the note name in our dictionary notes_dict,
  # so we can simply look it up :))
  return (out)
}

#' Convert semitones to Hz
#'
#' Internal soundgen function.
#'
#' Converts from semitones above C0 (~16.4 Hz) to Hz
#' @param s vector of frequencies (semitones above C0)
semitonesToHz = function(s) {
  out = sapply(s, function(x)
    16.3516 * 2 ^ (x / 12))
  return (out)
}


#' Convert to dB
#'
#' Internal soundgen function.
#' @param x a vector of floats between 0 and 1 (exclusive, i.e. these are ratios)
#' @example to_dB(c(.1, .5, .75, .9, .95, .99, .999, .9999))
to_dB = function(x) {
  return(10 * log10(x / (1 - x)))
}


#' Normalize 0 to 1
#'
#' Internal soundgen function
#'
#' Normalized input vector to range from 0 to 1
#' @param x numeric vector or matrix
zeroOne = function(x) {
  x = x - min(x)
  x = x / max(x)
}



#' Shannon entropy
#'
#' Internal soundgen function.
#'
#' Returns Weiner entropy of a power spectrum. Zeroes are dealt with by adding
#' 1e-10 to all elements. If all elements are zero, returns NA.
#' @param x vector of non-negative floats, e.g. a power spectrum
#' @return Float between 0 and 1 or NA
#' @examples
#' # a single peak in spectrum: entropy approaches 0
#' getEntropy(c(rep(0, 255), 1, rep(0, 256)))
#' # silent frame: entropy is NA
#' getEntropy(rep(0, 512))
#' # white noise: entropy = 1
#' getEntropy(rep(1, 512))
getEntropy = function(x, normalize = FALSE) {
  if (sum(x) == 0) return (NA)  # empty frames
  x = ifelse (x==0, 1e-10, x)  # otherwise log0 gives NaN
  geom_mean = exp(mean(log(x)))
  ar_mean = mean(x)
  return (geom_mean / ar_mean)
}


#' Random draw from a truncated normal distribution
#'
#' \code{rnorm_bounded} generates random numbers from a normal distribution
#' using rnorm(), but forced to remain within the specified low/high bounds. All
#' proposals outside the boundaries (exclusive) are discarded, and the sampling
#' is repeated until there are enough values within the specified range. Fully
#' vectorized.
#'
#' @param n the number of values to return
#' @param mean the mean of the normal distribution from which values are
#'   generated (vector of length 1 or n)
#' @param sd the standard deviation of the normal distribution from which values
#'   are generated (vector of length 1 or n)
#' @param low,high exclusive lower and upper bounds ((vectors of length 1 or n))
#' @param roundToInteger boolean vector of length 1 or n. If TRUE, the
#'   corresponding value is rounded to the nearest integer.
#' @return A vector of length n.
#' @examples
#' soundgen:::rnorm_bounded(n = 3, mean = 10, sd = 5, low = 7, high = NULL,
#'   roundToInteger = c(TRUE, FALSE, FALSE))
#' soundgen:::rnorm_bounded(n = 3, mean = c(10, 50, 100), sd = c(5, 0, 20),
#'   roundToInteger = TRUE) # vectorized
rnorm_bounded = function(n = 1,
                         mean = 0,
                         sd = 1,
                         low = NULL,
                         high = NULL,
                         roundToInteger = FALSE) {
  if (sum(mean > high | mean < low) > 0) {
    warning('Some of the specified means are outside the low/high bounds!')
  }
  if (sum(sd != 0) == 0) {
    out = rep(mean, n)
    out[roundToInteger] = round (out[roundToInteger], 0)
    return (out)
  }

  if (length(mean) < n) mean = rep(mean[1], n)
  if (length(sd) < n) sd = rep(sd[1], n)

  if (is.null(low) & is.null(high)) {
    out = rnorm(n, mean, sd)
    out[roundToInteger] = round (out[roundToInteger], 0)
    return (out)
  }

  if (is.null(low)) low = rep(-Inf, n)
  if (is.null(high)) high = rep(Inf, n)
  if (length(low) == 1) low = rep(low, n)
  if (length(high) == 1) high = rep(high, n)

  out = rnorm(n, mean, sd)
  out[roundToInteger] = round (out[roundToInteger], 0)
  for (i in 1:n) {
    while (out[i] < low[i] | out[i] > high[i]) {
      out[i] = rnorm(1, mean[i], sd[i]) # repeat until a suitable value is generated
      out[roundToInteger] = round (out[roundToInteger], 0)
    }
  }
  out
}


Mode = function(x) {
  # internal helper function for spectral (~BaNa) pitch tracker. NOT quite the same as simply mode(x)
  x = sort(x)
  ux <- unique(x)
  if (length(ux) < length(x)) {
    return (ux[which.max(tabulate(match(x, ux)))])
  } else {
    # if every element is unique, return the smallest
    return (x[1])
  }
}


#' Random walk
#'
#' Internal soundgen function.
#'
#' Generates a random walk with flexible control over its range, trend, and
#' smoothness. It works by calling \code{\link[stats]{rnorm}} at each step and
#' taking a cumulative sum of the generated values. Smoothness is controlled by
#' initially generating a shorter random walk and upsampling.
#' @param len an integer specifying the required length of random walk. If len
#'   is 1, returns a single draw from a gamma distribution with mean=1 and
#'   sd=rw_range
#' @param rw_range the upper bound of the generated random walk (the lower bound
#'   is set to 0)
#' @param rw_smoothing specifies the amount of smoothing, from 0 (no smoothing)
#'   to 1 (maximum smoothing to a straight line)
#' @param method specifies the method of smoothing: either linear interpolation
#'   ('linear', see \code{\link[stats]{approx}}) or cubic splines ('spline', see
#'   \code{\link[stats]{spline}})
#' @param trend mean of generated normal distribution (vectors are also
#'   acceptable, as long as their length is an integer multiple of len). If
#'   positive, the random walk has an overall upwards trend (good values are
#'   between 0 and 0.5 or -0.5). Trend = c(1,-1) gives a roughly bell-shaped rw
#'   with an upward and a downward curve. Larger absolute values of trend
#'   produce less and less random behavior
#' @return Returns a numeric vector of length len and range from 0 to rw_range.
#' @examples
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 5,
#'   rw_smoothing = .2))
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 15,
#'   rw_smoothing = .2, trend = c(.5, -.5)))
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 15,
#'   rw_smoothing = .2, trend = c(15, -1)))
getRandomWalk = function(len,
                         rw_range = 1,
                         rw_smoothing = .2,
                         method = c('linear', 'spline')[2],
                         trend = 0) {
  if (len < 2)
    return (rgamma(1, 1 / rw_range ^ 2, 1 / rw_range ^ 2))

  # generate a random walk (rw) of length depending on rw_smoothing, then linear extrapolation to len
  n = floor(max(2, 2 ^ (1 / rw_smoothing)))
  if (length(trend) > 1) {
    n = round(n / 2, 0) * 2 # force to be even
    trend_short = rep(trend, each = n / length(trend))
    # for this to work, length(trend) must be a multiple of n.
    # In practice, specify trend of length 2
  } else {
    trend_short = trend
  }

  if (n > len) {
    rw_long = cumsum(rnorm(len, trend_short)) # just a rw of length /len/
  } else {
    # get a shorter sequence and extrapolate, thus achieving more or less smoothing
    rw_short = cumsum(rnorm(n, trend_short)) # plot(rw_short, type = 'l')
    if (method == 'linear') {
      rw_long = approx(rw_short, n = len)$y
    } else if (method == 'spline') {
      rw_long = spline(rw_short, n = len)$y
    }
  } # plot (rw_long, type = 'l')

  # normalize
  rw_normalized = rw_long - min(rw_long)
  rw_normalized = rw_normalized / max(abs(rw_normalized)) * rw_range
  return (rw_normalized)
}


#' Discrete random walk
#'
#' Internal soudgen function.
#'
#' Takes a continuous random walk and converts it to continuous epochs of
#' repeated values 0/1/2, each at least minLength points long. 0/1/2 correspond
#' to different noise regimes: 0 = no noise, 1 = subharmonics, 2 = subharmonics
#' and jitter/shimmer.
#' @keywords internal
#' @param rw a random walk generated by \code{\link{getRandomWalk}} (expected
#'   range 0 to 100)
#' @param noise_amount a number between 0 to 100: 0 = returns all zeroes; 100 =
#'   returns all twos
#' @param minLength the mimimum length of each epoch
#' @return Returns a vector of integers (0/1/2) of the same length as rw.
#' @examples
#' rw = soundgen:::getRandomWalk(len = 100, rw_range = 100, rw_smoothing = .2)
#' plot (rw, type = 'l')
#' plot (soundgen:::getBinaryRandomWalk(rw, noiseAmount = 75, minLength = 10))
#' plot (soundgen:::getBinaryRandomWalk(rw, noiseAmount = 5, minLength = 10))
getBinaryRandomWalk = function(rw,
                               noiseAmount = 50,
                               minLength = 50) {
  len = length(rw)
  if (noiseAmount == 0) return(rep(0, len))
  if (noiseAmount == 100) return(rep(2, len))

  # calculate thresholds for different noise regimes
  q1 = noiseThresholds_dict$q1[noiseAmount + 1]
  # +1 b/c the rows indices in noiseThresholds_dict start from 0, not 1
  q2 = noiseThresholds_dict$q2[noiseAmount + 1]

  # convert continuous rw to discrete epochs based on q1 and q2 thresholds
  rw_bin = rep(0, len)
  rw_bin[which(rw > q1)] = 1
  rw_bin[which(rw > q2)] = 2   # plot (rw_bin, ylim=c(0,2))

  # make sure each epoch is long enough
  rw_bin = clumper(rw_bin, minLength = minLength)
  # plot (rw_bin, ylim = c(0,2))
  return (rw_bin)
}



#' Resize vector to required length
#'
#' Internal soundgen function.
#'
#' Adjusts a vector to match the required length by either trimming one or both
#' ends or padding them with zeros.
#' @param myseq input vector
#' @param len target length
#' @param padDir specifies the affected side. For padding, it is the side on
#'   which new elements will be added. For trimming, this is the side that will
#'   be trimmed. Defaults to 'central'
#' @param padWith if the vector needs to be padded to match the required length,
#'   what should it be padded with? Defaults to 0
#' @return Returns the modified vector of the required length.
#' @examples
#' soundgen:::matchLengths (c(1, 2, 3), len = 5)
#' soundgen:::matchLengths (3:7, len = 3)
#' # trimmed on the left
#' soundgen:::matchLengths (3:7, len = 3, padDir = 'left')
#' # padded with zeroes on the left
#' soundgen:::matchLengths (3:7, len = 30, padDir = 'left')
matchLengths = function(myseq,
                        len,
                        padDir = c('left', 'right', 'central')[3],
                        padWith = 0) {
  #  padDir specifies where to cut/add zeros ('left' / 'right' / 'central')
  if (length(myseq) == len) return (myseq)

  if (padDir == 'central') {
    if (length(myseq) < len) {
      myseq = c(rep(padWith, len), myseq, rep(padWith, len))
      # for padding, first add a whole lot of zeros and then trim using the same
      # algorithm as for trimming
    }
    halflen = len / 2
    center = (1 + length(myseq)) / 2
    start = ceiling(center - halflen)
    myseq = myseq[start:(start + len - 1)]
  } else if (padDir == 'left') {
    if (length(myseq) > len) {
      myseq = myseq [(length(myseq) - len + 1):length(myseq)]
    } else {
      myseq = c(rep(padWith, (len - length(myseq))), myseq)
    }
  } else if (padDir == 'right') {
    if (length(myseq) > len) {
      myseq = myseq [1:(length(myseq) - len)]
    } else {
      myseq = c(myseq, rep(padWith, (len - length(myseq))))
    }
  }
  return (myseq)
}


#' Add overlapping vectors
#'
#' Internal soundgen function.
#'
#' Adds two partly overlapping vectors to produce a longer vector. The location
#' at which vector 2 is pasted is defined by insertionPoint. Algorithm: both
#' vectors are padded with zeroes to match in length and then added. All NA's
#' are converted to 0.
#' @param v1,v2 numeric vectors
#' @param insertionPoint the index of element in vector 1 at which vector 2 will
#'   be insterted (any integer, can also be negative)
#' @examples
#' v1 = 1:6
#' v2 = rep(100, 3)
#' soundgen:::addVectors(v1, v2, insertionPoint = 5)
#' soundgen:::addVectors(v1, v2, insertionPoint = -4)
#' # note the asymmetry: insertionPoint refers to the first arg
#' soundgen:::addVectors(v2, v1, insertionPoint = -4)
#'
#' v3 = rep(100, 15)
#' soundgen:::addVectors(v1, v3, insertionPoint = -4)
#' soundgen:::addVectors(v2, v3, insertionPoint = 7)
addVectors = function(v1, v2, insertionPoint) {
  if (!is.numeric(v1)) stop(paste('Non-numeric v1:', head(v1)))
  if (!is.numeric(v2)) stop(paste('Non-numeric v2:', head(v2)))
  v1[is.na(v1)] = 0
  v2[is.na(v2)] = 0

  # align left ends
  if (insertionPoint > 1) {
    pad_left = insertionPoint - 1
    v2 = c(rep(0, insertionPoint), v2)
  } else if (insertionPoint < 1) {
    pad_left = 1 - insertionPoint
    v1 = c(rep(0, pad_left), v1)
  }

  # equalize lengths
  l1 = length(v1)
  l2 = length(v2)
  len_dif = l2 - l1
  if (len_dif > 0) {
    v1 = c(v1, rep(0, len_dif))
  } else if (len_dif < 0) {
    v2 = c(v2, rep(0, -len_dif))
  }

  return (v1 + v2)
}


#' Clump a sequence into large segments
#'
#' Internal soundgen function.
#'
#' \code{clumper} makes sure each homogeneous segment in a sequence is at least
#' minLength long. Called by getBinaryRandomWalk() and getVocalFry(). Algorithm:
#' go through the sequence once. If a short segment is encountered, it is pooled
#' with the previous one (i.e., the currently evaluated segment grows until it
#' is long enough, which may shorten the following segment). Finally, the last
#' segment is checked separately. This is CRUDE - a smart implementation is
#' pending!
#' @keywords internal
#' @param s a vector (soundgen supplies integers, but \code{clumper} also works
#'   on a vector of floats, characters or booleans)
#' @param minLength an integer or vector of integers indicating the desired
#'   length of a segment at each position (can vary with time, e.g., if we are
#'   processing pitch_per_gc values)
#' @return Returns the original sequence s transformed to homogeneous segments
#'   of required length.
#' @examples
#' s = c(1,3,2,2,2,0,0,4,4,1,1,1,1,1,3,3)
#' soundgen:::clumper(s, 2)
#' soundgen:::clumper(s, 3)
#' soundgen:::clumper(s, seq(1, 3, length.out = length(s)))
#' soundgen:::clumper(c('a','a','a','b','b','c','c','c','a','c'), 4)
clumper = function(s, minLength) {
  if (max(minLength) < 2) return(s)
  minLength = round(minLength) # just in case it's not all integers
  if (length(unique(s)) < 2 |
      (length(minLength) == 1 && length(s) < minLength) |
      length(s) < minLength[1]) {
    return(rep(round(median(s)), length(s)))
  }
  if (length(minLength)==1 |length(minLength)!=length(s)) {
    minLength = rep(minLength, length(s)) # upsample minLength
  }

  c = 0
  for (i in 2:length(s)) {
    if (s[i - 1] == s[i]) {
      c = c + 1
    } else {
      if (c < minLength[i]) {
        s[i] = s[i - 1] # grow the current segment until it is long enough
        c = c + 1
      } else {
        c = 1 # terminate the segment and reset the counter
      }
    }
  }

  # make sure the last epoch is also long enough
  idx_min = max((length(s) - tail(minLength, 1) + 1), 2):length(s)
  # these elements have to be homogeneous
  if (sum(s[idx_min] == tail(s, 1)) < tail(minLength, 1)) {
    # if they are not...
    idx = rev(idx_min)
    c = 1
    i = 2
    while (s[idx[i]] == s[idx[i] - 1] & i < length(idx)) {
      # count the number of repetitions for the last element
      c = c + 1
      i = i + 1
    }
    if (c < tail(minLength, 1)) {
      # if this number is insufficient,...
      s[idx] = s[min(idx_min)] # ...pool the final segment and the previous one
    }
  } # plot (s)
  return(s)
}

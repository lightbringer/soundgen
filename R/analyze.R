#' Analyze sound
#'
#' Acoustic analysis of a single sound file.
#'
#' @inheritParams spec
#' @param silence (0 to 1) frames with mean abs amplitude below silence threshold are not analyzed. NB: this number is dynamically updated: the actual silence threshold may be higher depending on the quietest frame, but it will never be lower than this specified number.
#' @param entropy_threshold frames with entropy above \code{entropy_threshold} are not analyzed (assumed to be just noise)
#' @param zpCep zero-padding of the spectrum used for cepstral pitch detection (points). Improves the precision of cepstral pitch detection quite noticeably.
#' @param pitch_floor,pitch_ceiling bounds for pitch candidates (Hz)
#' @param max_pitch_cands maximum number of pitch candidates to return. NB: only one dom and one pitchCep is returned, so the remaining candidates come from the autocorrelation and spectral pitch candidates.
#' @param voiced_threshold_autocor,voiced_threshold_cep,voiced_threshold_spec (0 to 1) separate thresholds for detecting pitch candidates with three different methods: autocorrelation, cepstrum, and BaNa algorithm (see Details). Note that HNR is still calculated for frames considered to be unvoiced.
#' @param specPitchThreshold_nullNA
#' @param slope_spec
#' @param width_spec
#' @param pitchSpec_only_peak_weight (0 to 1) if only one pitchSpec candidate is found, its weight (certainty) is taken to be \code{pitchSpec_only_peak_weight}. This mainly has implications for how much we trust the BaNa estimate vs. the autocorrelation estimate of f0.
#' @param prior_mean,prior_sd specifies the mean and sd of gamma distribution describing our prior knowledge about the most likely pitch values for this file (defaults to NA)
#' @param cutoff_dom do not consider frequencies above cutoff_dom when calculating the lowest dominant frequency band (recommended if the original sampling rate varies across different analyzed audio files)
#' @param dom_threshold (0 to 1) to find the lowest dominant frequency band, we do short-term FFT and take the lowest frequency with amplitude at least dom_threshold
#' @param shortest_syl the smallest length of a voiced segment (ms) that constitutes a syllable (shorter segments will be replaced by NA as if unvoiced)
#' @param shortest_pause the smallest gap between voiced syllables (ms) that means they shouldn't be merged into one voiced syllable
#' @param runSnake if TRUE, uses a stochastic algorithm for adjusting the pitch contour to minimize both the internal tension of the curve and its deviation from high-certainty pitch candidates. See \code{\link{snake}} for details. NB: if the snake is run, the final contour may deviate from the actually measured pitch candidates!
#' @param certWeight (0 to 1) in pitch postprocessing, specifies how much do we prioritize the certainty of pitch candidates vs. the internal tension of the resulting pitch curve. High certWeight: we mostly pay attention to our certainty in particular pitch candidates; low certWeight: we are more concerned with avoiding rapid pitch fluctuations in our contour.
#' @param snakeSmoothingStep controls the speed of snake adaptation
#' @param interpolWindow,interpolTolerance,interpolCert control the behavior of interpolation algorithm when evaluating the costs of possible snake configurations. See \code{\link{pathfinder}} for details.
#' @param plotSnake if TRUE, plots the snake (pitch postprocessing)
#' @param smooth if TRUE, contours of the specified variables (smooth_vars) are smoothed. To control the amount of smoothing, use \code{smooth_idx}.
#' @param smooth_vars apply a customized version of median smoothing to the contours of the variables in \code{smooth_vars} (defaults to \code{c('pitch', 'dom')}). Modifies only the values that deviate considerably from the moving median and preserves all other values (so this is a bit different from applying a moving median or kernel smoothing)
#' @param smooth_idx,smooth_vars if \code{smooth_idx} is a positive number, contours of the variables in \code{smooth_vars} are smoothed using a customized version of median smoothing. Modifies only the values that deviate considerably from the moving median and preserves all other values (so this is a bit different from applying a moving median or kernel smoothing). \code{smooth_idx} controls both the tolerated deviance and the size of the window for calculating a moving median. \code{smooth_idx} of 1 corresponds to a window of ~100 ms and tolerated deviation of ~4 semitones.
#' @param plot if TRUE, produces a spectrogram with pitch contour overlaid
#' @param savePath if a valid path is specified, the plot is saved in this folder (defaults to NA)
#' @param ... other graphical parameters passed to \code{\link{spec}}
#' @return Returns ... The best guess at the pitch contour considering all available information is stored in the variable called "pitch". In addition, the output contains pitch estimates based on three separate algorithms: autocorrelation (pitchAutocor), cepstrum (pitchCep), and BaNa (pitchSpec).
#' @export
#' @examples
#' sound = generateBout()
#' spec(sound, samplingRate = 16000)
analyzeSound = function (x,
                         samplingRate = NULL,
                         silence = 0.03,
                         entropy_threshold = 0.9,
                         windowLength = 50,
                         wn = 'gaussian',
                         step = 25,
                         zp = 0,
                         zpCep = 2 ^ 13,
                         pitch_floor = 75,
                         pitch_ceiling = 3500,
                         max_pitch_cands = 4,
                         voiced_threshold_autocor = 0.75,
                         voiced_threshold_cep = 0.45,
                         voiced_threshold_spec = 0.5,
                         specPitchThreshold_nullNA = 0.5,
                         slope_spec = 0.1,
                         width_spec = 150,
                         pitchSpec_only_peak_weight = 0.51,
                         prior_mean = NA,
                         prior_sd = NA,
                         cutoff_dom = 6000,
                         dom_threshold = 0.1,
                         shortest_syl = 20,
                         shortest_pause = 60,
                         interpolWindow = 3,
                         interpolTolerance = 0.3,
                         interpolCert = 0.3,
                         certWeight = .5,
                         runSnake = T,
                         snakeSmoothingStep = 0.05,
                         plotSnake = F,
                         smooth_idx = 1,
                         smooth_vars = c('pitch', 'dom'),
                         plot = T,
                         savePath = NA,
                         contrast = .2,
                         brightness = 0,
                         ylim = c(0, 5),
                         ...) {
  ## preliminaries
  # import a sound
  if (class(x) == 'character') {
    sound = tuneR::readWave(x)
    samplingRate = sound@samp.rate
    sound = sound@left
    plotname = tail(unlist(strsplit(soundfile, '/')), n = 1)
    plotname = substring (plotname, first = 1,
                          last = (nchar(plotname) - 4))
  }  else if (class(x) == 'numeric' & length(x) > 1) {
    if (is.null(samplingRate)) {
      stop ('Please specify samplingRate, eg 44100')
    } else {
      sound = x
      plotname = ''
    }
  }

  # normalize to range from no less than -1 to no more than +1
  if (min(sound) > 0) {
    sound = scale(sound)
  }
  sound = sound / max(abs(max(sound)), abs(min(sound)))

  windowLength_points = floor(windowLength / 1000 * samplingRate / 2) * 2
  # windowLength_points = 2^round (log(windowLength * samplingRate /1000)/log(2), 0) # to ensure that the window length in points is a power of 2, say 2048 or 1024
  duration = length(sound) / samplingRate
  maxNoCands = (max_pitch_cands - 2) %/% 2 # one for dom, one for pitchCep,
  # the rest shared between pitchAutocor and pitchSpec

  # Set up filter for calculating pitchAutocor
  filter = ftwindow_modif(2 * windowLength_points, wn = wn) # plot(filter, type='l')
  powerSpectrum_filter = abs(fft(filter)) ^ 2
  autoCorrelation_filter = abs(fft(powerSpectrum_filter, inverse = T)) ^ 2
  autoCorrelation_filter = autoCorrelation_filter[1:windowLength_points]
  autoCorrelation_filter = autoCorrelation_filter / max(autoCorrelation_filter)
  # plot(autoCorrelation_filter, type = 'l')

  ## fft and acf per frame
  if (!is.na(savePath)) {
    plot = T
    jpeg(file = paste0 (savePlotPath, plotname, ".jpg"), 1200, 800)
  }
  frameBank = getFrameBank(
    sound = sound,
    samplingRate = samplingRate,
    windowLength_points = windowLength_points,
    wn = wn,
    step = step,
    zp = zp,
    filter = NULL
  )
  s = spec(
    x = NULL,
    frameBank = frameBank,
    duration = duration,
    samplingRate = samplingRate,
    ylim = ylim,
    windowLength = windowLength,
    zp = zp,
    wn = wn,
    contrast = contrast,
    brightness = brightness,
    step = step,
    main = plotname,
    plot = plot,
    output = 'original',
    ...
  )
  autocorBank = apply (frameBank, 2, function(x)
    acf(x, windowLength_points, plot = F)$acf / autoCorrelation_filter)
  # plot (autocorBank[, 5], type = 'l')
  rownames(autocorBank) = samplingRate / (1:nrow(autocorBank))

  # calculate amplitude of each frame
  myseq = seq(1, (length(sound) - windowLength_points), length.out = ncol(s))
  ampl = apply (as.matrix(1:ncol(s)), 1, function(x) {
    # perceived intensity - root mean square of amplitude
    sqrt(mean(sound[myseq[x]:(myseq[x] + windowLength_points)] ^ 2))
  })
  # dynamically adjust silence threshold
  silence_threshold = max (silence, min(ampl))

  # calculate entropy of each frame within the most relevant
  # vocal range only: 50 to 6000 Hz
  rowLow = which(as.numeric(rownames(s)) > 0.05)[1] # 50 Hz
  rowHigh = which(as.numeric(rownames(s)) > 6)[1] # 6000 Hz
  entropy = apply (as.matrix(1:ncol(s)), 1, function(x) {
    getEntropy(s[rowLow:rowHigh, x])
  })
  # if the frame is too quiet or too noisy, we will not analyze it
  cond = (ampl > silence) & (entropy < entropy_threshold)

  ## spectral analysis of each frame from fft
  # set up an empty nested list to save values in - this enables us to analyze
  # only the non-silent and not-too-noisy frames but still have a consistently
  # formatted output
  frameInfo = rep(list(list(
    'pitch_array' = data.frame (
      'pitchCand' = NA,
      'pitchAmpl' = NA,
      'source' = NA,
      stringsAsFactors = F,
      row.names = NULL
    ),
    'summaries' = data.frame (
      'HNR' = NA,
      'dom' = NA,
      'peakFreq' = NA,
      'peakFreq_cut' = NA,
      'meanFreq' = NA,
      'quartile25' = NA,
      'quartile50' = NA,
      'quartile75' = NA,
      'specSlope' = NA
    )
  )), ncol(s))
  for (i in (1:ncol(s))[cond]) {
    # for each frame that satisfies our condition, do spectral analysis (NB: we
    # do NOT analyze frames that are too quiet or have very high entropy, so we
    # only get NA's for those frames, no meanFreq, dom etc!)
    frameInfo [[i]] = analyzeFrame(
      frame = s[, i],
      autoCorrelation = autocorBank[, i],
      samplingRate = samplingRate,
      windowLength_points = windowLength_points,
      wn = wn,
      zp = zp,
      zpCep = zpCep,
      cutoff_dom = cutoff_dom,
      voiced_threshold_autocor = voiced_threshold_autocor,
      voiced_threshold_cep = voiced_threshold_cep,
      voiced_threshold_spec = voiced_threshold_spec,
      specPitchThreshold_nullNA = specPitchThreshold_nullNA,
      slope_spec = slope_spec,
      width_spec = width_spec,
      pitch_floor = pitch_floor,
      pitch_ceiling = pitch_ceiling,
      silence = silence,
      dom_threshold = dom_threshold,
      pitchSpec_only_peak_weight = pitchSpec_only_peak_weight,
      autoCorrelation_filter = autoCorrelation_filter,
      maxNoCands = maxNoCands
    )
  }

  # Store the descriptives provided by function analyzeFrame in a dataframe
  summaries = lapply(frameInfo, function(y) y[['summaries']])
  result = do.call("rbind", summaries)
  result = as.data.frame (result)
  result$ampl = ampl
  result$entropy = entropy
  result$time = round(seq(
    windowLength_points / 2 / samplingRate,
    duration,
    length.out = nrow(result)
  ) * 1000,
  0)
  result$duration = duration
  rownames(result) = 1:nrow(result) # otherwise weird row names - bad for debugging

  ## postprocessing
  # extract and prepare pitch candidates for the pathfinder algorithm
  pitch_list = lapply(frameInfo, function(y) y[['pitch_array']])
  pitchCands = lapply(pitch_list, function(y) as.data.frame(t(y[['pitchCand']])))
  pitchCands = t(rbind.fill(pitchCands)) # a matrix of pitch candidates per frame
  pitchCert = lapply(pitch_list, function(y) as.data.frame(t(y[['pitchAmpl']])))
  pitchCert = t(rbind.fill(pitchCert)) # a matrix of our certainty in pitch candidates
  pitchSource = lapply(pitch_list, function(y) {
    # NB: without StringsAsFactors=F, the first row becomes "1"
    # because of wrong NA recognition
    as.data.frame(t(y[['source']]), stringsAsFactors = F)
  })
  pitchSource = t(rbind.fill(pitchSource)) # a matrix of the sources of pitch candidates

  # PRIOR for adjusting the estimated pitch certainties. For ex., if primarily
  # working with speech, we could prioritize pitch candidates in the expected
  # pitch range (100-1000 Hz) and dampen candidates with very high or very low
  # frequency as unlikely but still remotely possible in everyday vocalizing
  # contexts (think a soft pitch ceiling)
  if (!is.na(prior_mean) & !is.na(prior_sd)) {
    shape = log2(prior_mean) ^ 2 / log2(prior_sd) ^ 2
    rate = log2(prior_mean) / log2(prior_sd) ^ 2
    prior_normalizer = max(dgamma(
      log2(seq(pitch_floor, pitch_ceiling, length.out = 100)),
      shape = shape,
      rate = rate
    ))
    pitchCert = pitchCert * dgamma (
      log2(pitchCands),
      shape = shape,
      rate = rate
    ) / prior_normalizer
  }

  # divide the file into continuous voiced syllables
  analFrames = findVoicedSegments (
    pitchCands,
    shortest_syl = shortest_syl,
    shortest_pause = shortest_pause,
    step = step,
    samplingRate = samplingRate
  )

  # for each syllable, impute NA's and find a nice path through pitch candidates
  pitchFinal = rep(NA, ncol(pitchCands))
  if (nrow(analFrames) > 0) {
    # if we have found at least one putatively voiced syllable
    for (syl in 1:nrow(analFrames)) {
      myseq = analFrames$segmentStart[syl]:analFrames$segmentEnd[syl]
      # compute the optimal path through pitch candidates
      pitchFinal[myseq] = pathfinder(
        pitchCands = pitchCands[, myseq],
        pitchCert = pitchCert[, myseq],
        certWeight = certWeight,
        interpolWindow = interpolWindow,
        interpolTolerance = interpolTolerance,
        interpolCert = interpolCert,
        runSnake = runSnake,
        snakeSmoothingStep = snakeSmoothingStep,
        plotSnake = plotSnake
      )
    }
  }

  # save optimal pitch track and the best candidates separately for
  # autocor, cepstrum and spectral
  result$pitch = pitchFinal # optimal pitch track
  result$pitchAutocor = as.numeric(lapply(pitch_list, function(x) {
    x$pitchCand[x$source == 'autocor'] [which.max(x$pitchAmpl[x$source == 'autocor'])]
  }))
  result$pitchCepstrum = as.numeric(lapply(pitch_list, function(x) {
    x$pitchCand[x$source == 'cepstrum'] [which.max(x$pitchAmpl[x$source == 'cepstrum'])]
  }))
  result$pitchSpec = as.numeric(lapply(pitch_list, function(x) {
    x$pitchCand[x$source == 'spec'] [which.max(x$pitchAmpl[x$source == 'spec'])]
  }))

  ## Median smoothing of specified contours (by default pitch & dom)
  if (is.numeric(smooth_idx) && smooth_idx > 0) {
    points_per_sec = nrow(result) / duration
    # smooth_idx of 1 means that smoothing window is ~100 ms
    smoothing_ww = round (smooth_idx * points_per_sec / 10, 0)
    # the larger smooth_idx, the heavier the smoothing (lower tolerance
    # threshold before values are replaced by median over smoothing window).
    # smooth_idx of 1 gives smoothing_threshold of 4 semitones
    smoothing_threshold = 4 / smooth_idx
    result[smooth_vars] = medianSmoother (result[smooth_vars],
                                          smoothing_ww = smoothing_ww,
                                          smoothing_threshold = smoothing_threshold)
  }

  ## Having decided upon the pitch for each frame, we save certain measurements
  # only for voiced frames (with non-NA pitch)
  voiced_idx = which(!is.na(result$pitch))
  unvoiced_idx = which(is.na(result$pitch))
  result[unvoiced_idx, c('quartile25', 'quartile50', 'quartile75', 'ampl_voiced')] = NA
  result$ampl_voiced[voiced_idx] = result$ampl
  result$voiced = FALSE
  result$voiced[voiced_idx] = TRUE

  # Calculate the % of energy in harmonics based on the final pitch estimates
  threshold = 1.25 * result$pitch / 1000
  result$harmonics = apply(matrix(1:ncol(s)), 1, function(x) {
    ifelse(is.na(threshold[x]),
           NA,
           sum (s[as.numeric(rownames(s)) > threshold[x], x]) / sum (s[, x]))
  })

  # Convert HNR and harmonics to dB
  result$HNR = to_dB(result$HNR)
  result$harmonics = to_dB(result$harmonics)

  ## Add pitch contours to the spectrogram
  if (plot) {
    mylevels = c('autocor', 'cepstrum', 'spec', 'dom')
    mycols = c('green', 'violet', 'red', 'orange')
    mypch = c(16, 7, 2, 3)
    # pitchSource_1234 = apply(pitchSource, 2, function(x) match(x, mylevels))
    pitchSource_1234 = matrix(match(pitchSource, mylevels), ncol = ncol(pitchSource))
    for (r in 1:nrow(pitchCands)) {
      points (
        result$time,
        pitchCands[r, ] / 1000,
        col = mycols[pitchSource_1234[r, ]],
        pch = mypch[pitchSource_1234[r, ]],
        cex = pitchCert[r, ] * 2
      )
    }
    lines (result$time,
           result$pitch / 1000,
           col = 'blue',
           lwd = 3)
  }
  if (!is.na(savePath)) {
    dev.off()
  }

  result = result[c('duration', 'time', 'voiced', 'ampl', 'ampl_voiced',
                    'entropy', 'HNR', 'dom', 'meanFreq', 'peakFreq', 'peakFreq_cut',
                    'pitch', 'pitchAutocor', 'pitchCepstrum', 'pitchSpec',
                    'quartile25', 'quartile50', 'quartile75', 'specSlope', 'harmonics'
  )]
  return (result)
}

# example of use: a = analyzeSound ('soundfile.wav', plot=T)



analyzeFolder = function (folder,
                          silence = 0.03,
                          entropy_threshold = 0.9,
                          windowLength = 50,
                          wn = 'bartlett',
                          step = 25,
                          zp = 0,
                          zpCep = 2 ^ 13,
                          pitch_floor = 75,
                          pitch_ceiling = 3500,
                          max_pitch_cands = 4,
                          voiced_threshold_autocor = 0.75,
                          voiced_threshold_cep = 0.45,
                          voiced_threshold_spec = 0.5,
                          pitchSpec_only_peak_weight = 0.51,
                          specPitchThreshold_nullNA = 0.5,
                          slope_spec = 0.1,
                          width_spec = 150,
                          prior_mean = NA,
                          prior_sd = NA,
                          cutoff_dom = 6000,
                          dom_threshold = 0.1,
                          shortest_syl = 30,
                          shortest_pause = 40,
                          interpolWindow = 2,
                          interpolTolerance = 0,
                          interpolCert = 0.1,
                          certWeight = .5,
                          runSnake = T,
                          snakeSmoothingStep = 0.07,
                          plotSnake = F,
                          smooth = T,
                          smooth_idx = 2,
                          plot = T,
                          savePlot = F,
                          savePlotPath = '~/Downloads/temp/',
                          contrast = 1,
                          brightness = 1,
                          ylim = c(0, 5),
                          smooth_vars = c('pitch', 'dom'),
                          verbose = T) {
  # analyzes all .wav files in a folder. Returns a dataframe with acoustic descriptors and (optionally) saves the spectrograms with pitch contours

  ptm <- proc.time()
  filenames <-
    list.files(folder, pattern = "*.wav", full.names = TRUE)
  filesizes = apply (as.matrix(filenames), 1, function(x)
    file.info(x)$size) # in order to provide more accurate estimates of time to completion
  vars = c(
    'ampl',
    'ampl_voiced',
    'entropy',
    'HNR',
    'dom',
    'meanFreq',
    'peakFreq',
    'peakFreq_cut',
    'pitch',
    'pitchAutocor',
    'pitchCepstrum',
    'pitchSpec',
    'quartile25',
    'quartile50',
    'quartile75',
    'specSlope',
    'harmonics'
  )
  out = as.data.frame (matrix(
    ncol = 3 + 2 * length(vars),
    nrow = length(filenames)
  ))
  colnames(out)[c(1:3)] = c('file', 'duration', 'voiced')
  for (c in 1:length(vars)) {
    colnames(out)[3 + 2 * c - 1] = paste0(vars[c], '_', 'median') # specify how to summarize pitch etc values for each frame within each file - save median, sd, ... "3+2*c-1": "3" because of file/dur/voiced above, "+2*c" because for each acoustic variable, we save median and sd
    colnames(out)[3 + 2 * c] = paste0(vars[c], '_', 'sd')
  }
  myseq = (1:length(vars)) + 3 # which columns in the output of pitch_per_sound to save as median + sd

  for (i in 1:length(filenames)) {
    temp = analyzeSound (
      filenames[i],
      silence = silence,
      entropy_threshold = entropy_threshold,
      windowLength = windowLength,
      wn = wn,
      step = step,
      voiced_threshold_autocor = voiced_threshold_autocor,
      voiced_threshold_cep = voiced_threshold_cep,
      voiced_threshold_spec = voiced_threshold_spec,
      specPitchThreshold_nullNA = specPitchThreshold_nullNA,
      slope_spec = slope_spec,
      width_spec = width_spec,
      zp = zp,
      zpCep = zpCep,
      pitch_floor = pitch_floor,
      pitch_ceiling = pitch_ceiling,
      max_pitch_cands = max_pitch_cands,
      pitchSpec_only_peak_weight = pitchSpec_only_peak_weight,
      prior_mean = prior_mean,
      prior_sd = prior_sd,
      cutoff_dom = cutoff_dom,
      dom_threshold = dom_threshold,
      shortest_syl = shortest_syl,
      shortest_pause = shortest_pause,
      interpolWindow = interpolWindow,
      interpolTolerance = interpolTolerance,
      interpolCert = interpolCert,
      certWeight = certWeight,
      runSnake = runSnake,
      snakeSmoothingStep = snakeSmoothingStep,
      plotSnake = plotSnake,
      smooth = smooth,
      smooth_idx = smooth_idx,
      plot = plot,
      savePlot = savePlot,
      savePlotPath = savePlotPath,
      contrast = contrast,
      brightness = brightness,
      ylim = ylim,
      smooth_vars = smooth_vars
    )
    out[i, 1] = tail (unlist (strsplit(filenames[i], '/')), n = 1)
    out[i, 2] = temp[1, 'duration'] # duration, ms
    out[i, 3] = mean (temp[, 'voiced']) # proportion of voiced frames

    for (v in 1:length(myseq)) {
      myvar = colnames(temp)[myseq[v]]
      out[i, 2 * v + 2] = median (temp[, myvar], na.rm = T)
      out[i, 2 * v + 3] = sd (temp[, myvar], na.rm = T)
    }

    if (verbose) {
      time_elapsed = as.numeric ((proc.time() - ptm)[3])
      speed = time_elapsed / sum(filesizes[1:i])
      time_left = speed * sum(filesizes[min((i + 1), length(filesizes)):length(filesizes)])
      minutes = time_left %/% 60
      seconds = round (time_left %% 60, 0)
      if (minutes > 0) {
        report = paste0(
          'Done with file ',
          i,
          ' of ',
          length(filenames),
          '. Estimated time left: ',
          minutes,
          ' min ',
          seconds,
          ' sec.'
        )
      } else {
        report = paste0(
          'Done with file ',
          i,
          ' of ',
          length(filenames),
          '. Estimated time left: ',
          seconds,
          ' sec.'
        )
      }
      if (i < length(filenames)) {
        print(report)
      } else {
        minutes = time_elapsed %/% 60
        seconds = round (time_elapsed %% 60, 0)
        print (paste0(
          'Processed ',
          length(filenames),
          ' files in ',
          minutes,
          ' min ',
          seconds,
          ' sec.'
        ))
      }
    }
  }
  return (out)
}

# example of use:
# myfolder = '/home/allgoodguys/Documents/Studying/Lund_PhD/epistles/04_article_nat-actor/analysis/plots_ut590_pitch_july2016'
# df = analyzeFolder (myfolder, savePlot=F, plot=F, verbose=T, savePlotPath = paste0(myfolder,'/'))
# write.csv(df, '~/Downloads/ut590_july.csv')

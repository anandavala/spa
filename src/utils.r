#### Utils ####
library(dplyr)
library(ggplot2)
library(ggdendro)
library(cluster)
library(gtools)
library(igraph)
library(tidyr)

source("./src/map.R") # used to plot page rank results

row2CharVec <- function(df, r = 1) {
  if (!is.null(ncol(df))) {
    if (ncol(df) > 0) {
      out <- rep("", ncol(df))
      for (c in 1:ncol(df)) {
        out[c] <- as.character(df[r, c])
      }
      return(out)
    }
  }
  return(as.character(df))
}

# create a large set of double lettered labels
df <- expand.grid(LETTERS, LETTERS)
DBLLETTERS <- sprintf("%s%s", df$Var2, df$Var1)

# converts a numeric vector to a binned factor with a chosen number of bins
n2bf <- function(vec, nbins, doubling = FALSE, asint = FALSE) {
  if (doubling) template <- c(0, 1/2^seq(nbins - 1, 0, -1))
  else template <- seq(0, 1, length.out = nbins + 1)
  s <- summary(vec)
  if (asint) {
    smin <- as.integer(floor(s["Min."]))
    smax <- as.integer(floor(s["Max."]))
  }
  else {
    smin <- s["Min."]
    smax <- s["Max."]
  }
  breaks <- c(smin - 1)
  labels <- c(as.character(smin))
  range <- smax - smin
  for (b in 1:(nbins - 1)){
    if (asint) {
      brk <- round(smin + range * template[b+1])
      prevBrk <- round(smin + range * template[b])
      labels <- c(labels, sprintf("%d-%d", prevBrk, brk))
    }
    else {
      brk <- smin + range * template[b+1]
      prevBrk <- smin + range * template[b]
      labels <- c(labels, sprintf("%0.2f-%0.2f", prevBrk, brk))
    }
    breaks <- c(breaks, brk)
  }
  breaks <- c(breaks, smax)
  if (asint) {
    prevBrk <- round(smin + range * template[nbins])
    labels <- c(labels, sprintf("%d-%d", prevBrk, smax))
  }
  else {
    prevBrk <- smin + range * template[nbins]
    labels <- c(labels, sprintf("%0.2f-%0.2f", prevBrk, smax))
  }
  return(cut(vec, breaks = breaks, labels = labels[2:length(labels)]))
}

# plot a sorted data frame
# first sort the values, then plot them to see how they vary over the spectrum
sortedPlot <- function(df, sortby, lblsize = NULL, datatype = "", ylabel = "", ptsize = 1, suffix = "") {
  df <- df[order(eval(parse(text = paste("df$", sortby, sep = "")))), ]
  rank <- 1:nrow(df)
  plt <- ggplot(df, aes(x = rank, y = eval(parse(text = sortby)))) +
    geom_point(size = ptsize) +
    scale_x_continuous(breaks = rank, labels = rownames(df)) +
    theme(axis.text.x = element_text(face="bold", angle=90, size = lblsize)) +
    ylab(ylabel) +
    xlab(sprintf("%s sorted by ascending %s values", datatype, sortby)) +
    ggtitle(sprintf("Sorted Plot: %s", suffix), subtitle = sprintf("%s for %s sorted by ascending %s values", sortby, datatype, sortby))
  if (!is.null(lblsize)) {
    plt <- plt + 
      scale_x_continuous(breaks = rank, labels = rownames(df)) +
      theme(axis.text.x = element_text(face="bold", angle=90, size = lblsize))
  }
  plt
}

numChar <- function(vec, chr) { # vec is vector of characters
  if (length(vec) == 0) return(0)
  count <- 0
  for (i in 1:length(vec)) {
    if (vec[i] == chr) count <- count + 1
  }
  return(count)
}

numX <- function(vec) { # vec is vector of characters
  return(numChar(vec, "X"))
}

numCX <- function(vec) { # vec is vector of characters and the X is in complex form, i.e. "A>X"
  numxs <- 0
  for (p in seq(length(vec))) {
    subVec <- strsplit(vec[p], split = ">")[[1]]
    if (length(subVec) == 2 & subVec[2] == "X") {
      numxs <- numxs + 1
    }
  }
  return(numxs)
}

# return the row number for a given symbol within a given dimension
getRowOfParam <- function(s, colNum, symSet) {
  for (r in 3:sum(!is.na(symSet[,colNum]))) {
    if (symSet[r,colNum] == sprintf("%s", s)) return(r)
  }
  return(0)
}

complexSymSet <- function(symSet) {
  maxSyms <- nrow(symSet) - 2
  newSymSet <- data.frame(matrix(NA, nrow = maxSyms * 2 + 1, ncol = ncol(symSet)))
  for (c in seq(ncol(symSet))) {
    totalSyms <- sum(!is.na(symSet[,c]))
    availSyms <- symSet[3:totalSyms, c]
    nsyms <- totalSyms - 2
    newSymSet[seq(nsyms), c] <- paste(availSyms, rep("X", nsyms), sep = ">")
    newSymSet[(nsyms+1):(2*nsyms+1), c] <- as.character(as.vector(symSet[2:totalSyms, c]))
  }
  return(newSymSet)
}

getMasks <- function(symSet, masks = c(), str = rep("", ncol(symSet)), iter = 1, constraints = rep("", ncol(symSet))) {
  if (iter == 1) symSet <- complexSymSet(symSet)
  if (constraints[iter] != "") {
    r <- c(1)
    syms <- c(constraints[iter])
  }
  else {
    r <- 1:sum(!is.na(symSet[,iter]))
    syms <- symSet[, iter]
  }
  for (s in r) {
    str[iter] <- sprintf("%s", syms[s])
    if (iter < ncol(symSet)) masks <- getMasks(symSet, masks, str, iter + 1, constraints = constraints)
    else if (numCX(str) == 1) masks <- append(masks, paste(str, sep = "", collapse = ","))
  }
  return(masks)
}

colFromList <- function(lst, cnum) {
  out <- c()
  for (i in 1:length(lst)) {
    out <- c(out, lst[[i]][cnum])
  }
  return(out)
}

num_ <- function(vec) { # vec is a vector of strings
  return(numChar(vec, "_"))
}

# function, given a mask compute some statistics for the associated group of types
getScenarios <- function(df, symSet, masks = getMasks(symSet), ppCol = "PP", nSkip = 0) {
  groupAPs <- c()
  ratios <- list()
  pps <- list()
  diffs <- list()
  params <- list()
  origdf <- df
  maxSyms <- nrow(symSet) - 2
  maxp <- ncol(symSet)
  for (mask in masks) {
    df <- origdf
    pp <- 1:maxp # possible positions
    xp <- 0 # X position
    vec <- strsplit(mask, split = ",")[[1]]
    for (p in 1:maxp) {
      if (p > length(params)) params[[p]] <- c(vec[p])
      else params[[p]] <- append(params[[p]], vec[p])
      subVec <- strsplit(vec[p], split = ">")[[1]]
      if (length(subVec) == 2 & subVec[2] == "X") {
        pp <- pp[pp!=p]
        xp <- p
        initState <- subVec[1]
        origR <- getRowOfParam(initState, xp, symSet)
      }
      else if (vec[p] == "_") {
        pp <- pp[pp!=p]
      }
    }
    if (length(pp) > 0) {
      for (i in 1:length(pp)) {
        tmp <- split(df, df[, nSkip + pp[i]])
        df <- eval(parse(text = paste("tmp[[\"", vec[pp[i]], "\"]]", sep = "")))
      }
    }
    tmp <- split(df, df[, nSkip + xp])
    nsyms <- sum(!is.na(symSet[,xp])) - 2
    syms <- as.character(as.vector(symSet[3:sum(!is.na(symSet[,xp])), xp]))
    ps <- rep(NA, nsyms)
    for (i in 1:nsyms) {
      ps[i] <- sum(eval(parse(text = paste("(tmp[[syms[i]]])$", ppCol, sep = ""))))
    }
    sumps <- sum(ps)
    pp <- rep(NA, nsyms)
    ratio <- rep(NA, nsyms)
    diff <- rep(NA, nsyms)
    for (i in 1:nsyms) {
      pp[i] <- ps[i] #/ sumps * 100
      avgOther <- mean(ps[c(-i)])
      ratio[i] <- ps[i] / avgOther # ratio between each and the average other
      # diff[i] <- ps[i] - avgOther # difference between each and the average other
      diff[i] <- ps[i] - ps[origR - 2] # difference between each and the initial state
      # TODO need to think about this!
    }
    groupAPs <- append(groupAPs, sumps)
    ratios <- append(ratios, list(ratio))
    pps <- append(pps, list(pp))
    diffs <- append(diffs, list(diff))
  }
  num_vec <- rep(NA, length(masks))
  for (m in seq(length(masks))) {
    num_vec[m] <- num_(strsplit(masks[m], split = ",")[[1]])
  }
  out <- data.frame(row.names = masks, 
                    Mask = masks,
                    N_ = num_vec)
  out$Mask <- as.character(out$Mask)
  for (i in 1:maxp) {
    eval(parse(text = paste("out$D", i, " <- params[[i]]", sep = "")))
  }
  out$GroupAP = groupAPs
  for (i in 1:maxSyms) {
    eval(parse(text = paste("out$R", i, " <- colFromList(ratios, i)", sep = "")))
  }
  for (i in 1:maxSyms) {
    eval(parse(text = paste("out$PP", i, " <- colFromList(pps, i)", sep = "")))
  }
  for (i in 1:maxSyms) {
    eval(parse(text = paste("out$Diff", i, " <- colFromList(diffs, i)", sep = "")))
  }
  for (i in 1:maxSyms) {
    eval(parse(text = paste("out$DP", i, " <- out$GroupAP / 100 * out$Diff", i, sep = "")))
  }
  for (i in 1:maxSyms) {
    eval(parse(text = paste("out$TP", i, " <- out$Diff", i, " / out$GroupAP * 100", sep = "")))
  }
  return(out)
}

getPathOnDemand <- function(tf, symSet, chosen = rep("",ncol(symSet)), choices, withTotals = TRUE, ppCol = "PP", nSkip = 0, undef = numChar(chosen, "") - 1) {
  if (length(choices) > 0) {
    choice = choices[1]
    if (length(choices) > 1) choices <- choices[2:length(choices)]
    else choices <- c()
    cs <- strsplit(choice, split = ",")[[1]]
    c <- as.integer(cs[1])
    r <- getRowOfParam(as.character(cs[2]), c, symSet)
    if (undef < 0) {
      undef <- 0
    }
    # create a scenario set with dim c == "X" and N_ == undef
    chosen[c] <- sprintf("%s>X", chosen[c])
    masks <- getMasks(symSet, constraints = chosen)
    chosen[c] <- as.character(cs[2])
    masks <- masks[num_(masks) == undef]
    mbs <- getScenarios(tf, symSet, masks, ppCol, nSkip)
    mbs$Choice <- as.character(cs[2])
    mbs$ChDiff <- eval(parse(text = paste("mbs$Diff", r - 2, sep = "")))
    mbs$ChDP <- eval(parse(text = paste("mbs$DP", r - 2, sep = "")))
    mbs$ChTP <- eval(parse(text = paste("mbs$TP", r - 2, sep = "")))
    df1 <- select(mbs, GroupAP, Choice, ChDiff, ChDP, ChTP)
    df2 <- getPathOnDemand(tf, symSet, chosen, choices, FALSE, ppCol, nSkip, undef - 1)
    if (!is.null(df2)) df2 <- select(df2, GroupAP, Choice, ChDiff, ChDP, ChTP)
    if (withTotals) {
      df12 <- rbind(df1, df2)
      df3 <- data.frame(GroupAP = c("","",""), Choice = c("","",""), ChDiff = c("","",""), ChDP = c("","",""), ChTP = c("","",""))
      rownames(df3) <- c("-------" ,"Totals", "Averages")
      n <- nrow(df12)
      df3$GroupAP<- c("", sum(df12$GroupAP), sum(df12$GroupAP) / n)
      df3$ChDiff<- c("", sum(df12$ChDiff), sum(df12$ChDiff) / n)
      df3$ChDP <- c("", sum(df12$ChDP), sum(df12$ChDP) / n)
      df3$ChTP <- c("", sum(df12$ChTP), sum(df12$ChTP) / n)
      return(rbind(df12, df3))
    }
    else {
      return(rbind(df1, df2))
    }
  }
}


# each path is defined by a set of four choices, e.g. c("1,A", "2,B", "3,A", "2,A")
# traverse this sequence of choices and print details of each step
getPath <- function(mbs, choices, symSet, chosen = rep("",ncol(symSet)), undef = numChar(chosen, "") - 1, withTotals = TRUE, origmbs = mbs) {
  if (length(choices) > 0) {
    choice = choices[1]
    if (length(choices) > 1) choices <- choices[2:length(choices)]
    else choices <- c()
    cs <- strsplit(choice, split = ",")[[1]]
    c <- as.integer(cs[1])
    r <- getRowOfParam(as.character(cs[2]), c, symSet)
    origState <- chosen[c]
    if (undef < 0) {
      undef <- 0
      chosen[c] <- sprintf("%s>X", origState)
      mbs <- origmbs[getMasks(symSet, constraints = chosen),]
    }
    chosen[c] <- as.character(cs[2])
    mbs$Choice <- as.character(cs[2])
    mbs$ChDiff <- eval(parse(text = paste("mbs$Diff", r - 2, sep = "")))
    mbs$ChDP <- eval(parse(text = paste("mbs$DP", r - 2, sep = "")))
    mbs$ChTP <- eval(parse(text = paste("mbs$TP", r - 2, sep = "")))
    df1 <- mbs[eval(parse(text = paste("mbs$D", c, sep = ""))) == sprintf("%s>X", origState) & mbs$N_ == undef, ]
    df1 <- select(df1, GroupAP, Choice, ChDiff, ChDP, ChTP)
    df2 <- getPath(mbs[eval(parse(text = paste("mbs$D", c, sep = ""))) == symSet[r,c], ], choices, symSet, chosen, undef - 1, FALSE, origmbs = origmbs)
    if (!is.null(df2)) df2 <- select(df2, GroupAP, Choice, ChDiff, ChDP, ChTP)
    if (withTotals) {
      df12 <- rbind(df1, df2)
      df3 <- data.frame(GroupAP = c("","",""), Choice = c("","",""), ChDiff = c("","",""), ChDP = c("","",""), ChTP = c("","",""))
      rownames(df3) <- c("-------" ,"Totals", "Averages")
      n <- nrow(df12)
      df3$GroupAP<- c("", sum(df12$GroupAP), sum(df12$GroupAP) / n)
      df3$ChDiff<- c("", sum(df12$ChDiff), sum(df12$ChDiff) / n)
      df3$ChDP <- c("", sum(df12$ChDP), sum(df12$ChDP) / n)
      df3$ChTP <- c("", sum(df12$ChTP), sum(df12$ChTP) / n)
      return(rbind(df12, df3))
    }
    else {
      return(rbind(df1, df2))
    }
  }
}


getTypes <- function(symSet) {
  entries <- list()
  ncols <- ncol(symSet)
  for (c in 1:ncols) {
    syms <- as.character(as.vector(symSet[3:sum(!is.na(symSet[,c])), c]))
    # for (s in 1:length(syms)) {
    #   syms[s] <- paste(as.character(c), syms[s], sep = ",")
    # }
    entries <- append(entries, list(syms))
  }
  
  return(expand.grid(entries, stringsAsFactors = FALSE))
}


getPerms <- function(symSet) {
  entries <- list()
  ncols <- ncol(symSet)
  for (c in 1:ncols) {
    syms <- as.character(as.vector(symSet[3:sum(!is.na(symSet[,c])), c]))
    for (s in 1:length(syms)) {
      syms[s] <- paste(as.character(c), syms[s], sep = ",")
    }
    entries <- append(entries, list(syms))
  }
  
  types <- expand.grid(entries, stringsAsFactors = FALSE)
  
  perms <- matrix(ncol = ncols)
  for (i in 1:nrow(types)) {
    p1 <- permutations(ncols, ncols, as.character(as.vector(types[i,])), set = TRUE)
    perms <- rbind(perms, p1)
  }
  perms <- data.frame(na.omit(perms), stringsAsFactors = FALSE)
  for (r in 1:nrow(perms)) {
    dims <- as.character(as.vector(perms[r,]))
    for (i in 1:length(dims)) dims[i] <- substring(dims[i], nchar(dims[i]), nchar(dims[i]))
  }
  out <- data.frame(Ch1 = perms[,1])
  for (c in 2:ncols) {
    eval(parse(text = paste("out$Ch", c, " <- perms[, c]", sep = "")))
  }
  return(out)
}
  
getAllPaths <- function(mbs, symSet, chosen = rep("",ncol(symSet)), avgs = TRUE) {
  out <- getPerms(symSet)
  TGroupAP <- c()
  TChDiff <- c()
  TChDP <- c()
  TChTP <- c()
  for (i in 1:nrow(out)) {
    pathDf <- getPath(mbs, row2CharVec(out[i, ]), symSet, withTotals = FALSE, chosen = chosen)
    n <- nrow(pathDf)
    TGroupAP <- append(TGroupAP, sum(pathDf$GroupAP) / ifelse(avgs, n, 1))
    TChDiff <- append(TChDiff, sum(pathDf$ChDiff) / ifelse(avgs, n, 1))
    TChDP <- append(TChDP, sum(pathDf$ChDP) / ifelse(avgs, n, 1))
    TChTP <- append(TChTP, sum(pathDf$ChTP) / ifelse(avgs, n, 1))
  }
  out <- cbind(out, TGroupAP, TChDiff, TChDP, TChTP)
  for (c in 1:ncol(symSet)) {
    out[,c] <- as.factor(out[,c])
  }
  return(out)
}

standardiseLevels <- function(column) {
  return(gsub("[^A-Za-z0-9]", "_", levels(column)))
}

getSymSetFromTF <- function(tf, symCols) {
  prefix <- c("X", "_")
  maxLvls <- 0
  for (c in symCols) {
    lvlLen <- length(levels(tf[,c]))
    if (lvlLen > maxLvls) maxLvls <- lvlLen
  }
  symSet <- data.frame(c1 = rep(NA, maxLvls + 2))
  for (c in symCols) {
    lvls <- levels(tf[,c])
    syms <- c(prefix, lvls)
    if (length(syms) < maxLvls + 2) {
      syms <- c(syms, rep(NA, maxLvls + 2 - length(syms)))
    }
    eval(parse(text = paste("symSet$c", c - symCols[1] + 1, " <- syms", sep = "")))
  }
  colnames(symSet) <- colnames(tf)[symCols]
  return(symSet)
}

# build symbolset from data about individuals
getSymSetFromData <- function(Data) {
  prefix <- c("X", "_")
  maxLvls <- 0
  for (c in 1:ncol(Data)) {
    lvlLen <- length(levels(Data[,c]))
    if (lvlLen > maxLvls) maxLvls <- lvlLen
  }
  symSet <- data.frame(c1 = rep(NA, maxLvls + 2))
  for (c in 1:ncol(Data)) {
    lvls <- levels(Data[,c])
    syms <- c(prefix, lvls)
    if (length(syms) < maxLvls + 2) {
      syms <- c(syms, rep(NA, maxLvls + 2 - length(syms)))
    }
    eval(parse(text = paste("symSet$c", c, " <- syms", sep = "")))
  }
  colnames(symSet) <- colnames(Data)
  return(symSet)
}

# spec is a list of vectors 
getSymSetFromSpec <- function(spec) {
  nrows <- 0
  for (item in spec) if (length(item) > nrows) nrows <- length(item)
  m <- matrix(NA, nrow = nrows + 2, ncol = length(spec))
  for (i in seq(length(spec))) {
    len <- length(spec[[i]])
    m[seq(len+2),i] <- c("X", "_", spec[[i]])
  }
  return(data.frame(m, stringsAsFactors = FALSE))
}


# build type frequency table
getTypeFreqs <- function(Data, symSet, dims = 1:ncol(Data)) {
  types <- getTypes(symSet)
  colnames(types) <- colnames(Data)[dims]
  # collect count stats for types in the population
  types$Count <- rep(NA, nrow(types))
  for (t in 1:nrow(types)) {
    str <- "df <- filter(Data,"
    for (c in 1:length(dims)) {
      str <- paste(str,"Data[,", dims[c], "] == types[", t, ",", c, "]", ifelse(c == length(dims), " )", " & "), sep = "")
    }
    eval(parse(text = str))
    types$Count[t] <- nrow(df)
  }
  # calculate the percentage prevalence stats for each type
  types <- types %>%
    mutate(PP = Count / sum(Count) * 100) %>%
    select(-Count)
  # change dims to factors
  for (c in 1:(ncol(types) - 1)) {
    types[,c] <- factor(types[,c])
  }
  return(types)
}


# given a type-freq table, what are the pressures on a particular type?
# The pressures on the first dimension are shown in the bottom line,
# up to the last dimension in the top line.
# Positive values indicate pressure to remain the same,
# negative values indicate pressure to change.
getPressures <- function(tf, symSet, chosen, ppCol = "PP", nSkip = 0) {
  out <- list()
  for (i in ncol(symSet):1) {
    tmp <- data.frame()
    nsyms <- sum(!is.na(symSet[,i])) - 2
    syms <- symSet[3:(nsyms+2),i]
    for (s in syms) {
      tmp <- rbind(tmp, getPathOnDemand(tf, symSet, chosen, c(paste(i, s, sep = ",")), FALSE, ppCol, nSkip))
    }
    tmp <- tmp[tmp$Choice != chosen[i],]
    out <- append(out, list(tmp))
  }
  return(out)
}

# only works with binary symbol sets, or the first two elements of non-binary
flipTaiji <- function(chosen, l, symSet) {
  str <- chosen[l]
  if (str == symSet[3,l]) return(as.character(symSet[4,l]))
  else if (str == symSet[4,l]) return(as.character(symSet[3,l]))
  else return(NA)
}

# works with any symbol set
getChanges <- function(chosen, l, symSet) {
  str <- chosen[l]
  options <- as.character(symSet[3:sum(!is.na(symSet[,l])),l])
  return(options[options != str])
}

addWidth <- function(g) {
  if (!is.null(E(g)$weight)) {
    minW <- min(E(g)$weight)
    maxW <- max(E(g)$weight)
    if ((maxW - minW) != 0) E(g)$width <- (E(g)$weight - minW) / (maxW - minW) * 9 + 1
    else E(g)$width <- rep(2, ecount(g))
  }
  return(g)
}


# with onlyMax == FALSE we consider all lines of a hexagram
# with onlyMax == TRUE we only consider the lines of a hexagram with maximum pressure
# the former is better for finding all pressured changes, 
# but the latter is better for visualising the overall structure of connections
mkGraph <- function(tf, symSet, onlyMax = FALSE, useSimilarity = FALSE, ppCol = "PP", nSkip = 0) {
  ndims <- ncol(symSet)
  orderedTF <- tf[order(tf[,ppCol]), ]
  diffCol <- "ChDiff" # need to fix similarity code if this is changed because it is hardwired there
  g<- graph.empty(nrow(orderedTF), directed = TRUE)
  V(g)$name <- rownames(tf)
  maxChoicePressure <- orderedTF[, ppCol][length(orderedTF[, ppCol])] - orderedTF[, ppCol][1]
  for (i in 1:nrow(orderedTF)) {
    hexId <- rownames(orderedTF)[i]
    chosen <- row2CharVec(orderedTF[i,(nSkip + 1):(ndims + nSkip)])
    p <- getPressures(orderedTF, symSet, chosen, ppCol, nSkip)
    names(p) <- ndims:1
    # optionally switch to using similarity instead of ChDiff
    # it would still be called ChDiff but would measure similarity instead
    if (useSimilarity) for (l in ndims:1) p[[as.character(l)]]$ChDiff <- 1 / p[[as.character(l)]]$ChDiff
    if (onlyMax) {
      maxV <- c()
      for (l in ndims:1) {
        maxV[l] <- max(p[[as.character(l)]]$ChDiff)
      }
      maxV <- max(maxV)
      for (l in ndims:1) {
        p[[as.character(l)]] <- p[[as.character(l)]][p[[as.character(l)]]$ChDiff == maxV,]
      }
    }
    for (l in ndims:1) {
      maxp <- p[[as.character(l)]]
      if (nrow(maxp) > 0) {
        for (r in 1:nrow(maxp)) { # for each option for this line
          linePressure <- maxp[r, diffCol]
          if (linePressure > 0) {
            choice <- maxp[r, "Choice"]
            newChosen <- chosen
            newChosen[l] <- choice
            evalStr <- paste("rownames(orderedTF[orderedTF[,", nSkip + 1, "] == newChosen[1]", sep = "")
            if (ndims > 1) {
              for (c in 2:ndims) {
                evalStr <- paste(evalStr, " & orderedTF[,", nSkip + c, "] == newChosen[", c, "]", sep = "")
              }
            }
            evalStr <- paste(evalStr, ", ])", sep = "")
            newHexId <- eval(parse(text = evalStr))
            if (length(newHexId) == 1) {
              g <- add.edges(g, c(hexId,newHexId), weight = c(linePressure), line = l)
            }
          }
        }
      }
    }
  }
  if (useSimilarity) { # check for Inf weight edges due to zero differences
    maxNotInf <- max(E(g)$weight[!is.infinite(E(g)$weight)])
    E(g)$weight[is.infinite(E(g)$weight)] <- maxNotInf * 1.3
  }
  if (useSimilarity) E(g)$color <- rep("#8fb7b4", ecount(g))
  else E(g)$color <- rep("#a377b2", ecount(g))
  return(addWidth(g))
}

getPageRanked <- function(g, doPlot = TRUE, layoutFunc = NULL, layout = NULL, withPlot = TRUE) {
  pr <- page.rank(g)$vector
  if (withPlot) {
    if (is.null(layout)) {
      if (is.null(layoutFunc)) {
        layout <- layout.auto(g)
      }
      else {
        layout <- layoutFunc(g)
      }
    }
    if (!is.null(E(g)$weight)) eqarrowPlot(g, layout, edge.arrow.size=E(g)$width/8,
                                           edge.width=E(g)$width, edge.color=E(g)$color, edge.label = NA, pr = pr)
    else eqarrowPlot(g, layout, edge.arrow.size=1,
                     edge.width=1, edge.label = NA, pr = pr)
  }
  return(pr)
}

getDecomposition <- function(g) {
  dg <- decompose.graph(g) # returns a list of subgraphs
  dgEdges <- list()
  dgVertices <- list()
  dgMaxPressure <- list()
  for (i in 1:length(dg)) {
    tmpg <- dg[[i]]
    edges <- as.data.frame(get.edgelist(tmpg))
    dgVertices <- append(dgVertices, list(V(tmpg)))
    if (nrow(edges) > 0) {
      edges$line <- E(tmpg)$line
      edges$weight <- E(tmpg)$weight
      edges <- edges[order(-edges$weight),]
      dgEdges <- append(dgEdges, list(edges))
      dgMaxPressure <- append(dgMaxPressure, list(edges[1, "weight"]))
    }
    else {
      dgEdges <- append(dgEdges, list(edges))
      dgMaxPressure <- append(dgMaxPressure, list(0))
    }
  }
  weightOrder <- order(-colFromList(dgMaxPressure, 1))
  return(list(dg = dg, dgEdges = dgEdges, dgVertices = dgVertices, dgMaxPressure = dgMaxPressure, weightOrder = weightOrder))
}

# adapted from: https://stackoverflow.com/questions/16942553/a-hack-to-allow-arrows-size-in-r-igraph-to-match-edge-width
eqarrowPlot <- function(graph, layout, edge.lty=rep(1, ecount(graph)),
                        edge.arrow.size=rep(1, ecount(graph)),
                        edge.width=rep(1, ecount(graph)),
                        edge.color=rep("grey", ecount(graph)),
                        edge.label=rep(NA, ecount(graph)),
                        vertex.shape="circle",
                        edge.curved=autocurve.edges(graph), pr, ...) {
  mapResf <- map(pr, c(10,15))
  plot.igraph(graph, edge.lty=0, edge.arrow.size=0, layout=layout,
       vertex.shape="none", vertex.label=NA)
  for (e in seq_len(ecount(graph))) {
    graph2 <- delete.edges(graph, E(graph)[(1:ecount(graph))[-e]])
    plot.igraph(graph2, edge.lty=edge.lty[e], edge.arrow.size=edge.arrow.size[e],
         edge.width=edge.width[e],
         edge.label = edge.label[e],
         edge.color = edge.color[e],
         edge.curved=edge.curved[e], layout=layout, vertex.shape="none",
         vertex.label=NA, add=TRUE, ...)
  }
  plot.igraph(graph, edge.lty=0, edge.arrow.size=0, layout=layout,
       vertex.shape=vertex.shape, 
       vertex.size=mapResf[V(graph)$name], vertex.color=mapResf[V(graph)$name], vertex.label.font = 2, vertex.label.cex = 1, vertex.label.dist = 1.5,
       add=TRUE, ...)
  invisible(NULL)
}

analyseSubgraph <- function(decomp, rank, interactive = TRUE, getResult = FALSE, pr, urlTemplate = c(), layoutFunc = layout.auto) {
  ind <- decomp$weightOrder[rank]
  tmpg <- decomp$dg[[ind]]
  edges <- decomp$dgEdges[[ind]]
  origRows <- nrow(edges)
  if (length(urlTemplate) > 0 & origRows > 0) {
    id1 <- regmatches(edges$V1, regexpr("[0-9]+", edges$V1, perl=TRUE))
    id2 <- regmatches(edges$V2, regexpr("[0-9]+", edges$V2, perl=TRUE))
    edges$url <- paste(urlTemplate[1], id1, urlTemplate[2], id2, urlTemplate[3], sep = "")
  }
  if (interactive) {
    print(names(decomp$dgVertices[[ind]]))
    if (nrow(edges) > 0) {
      print(edges)
    }
  }
  if (interactive & origRows > 0) {
    mapResf <- map(pr, c(10,15))
    # plot.igraph(tmpg, layout=layout, vertex.size=mapResf[V(tmpg)$name], vertex.color=mapResf[V(tmpg)$name], vertex.label.font = 2, vertex.label.cex = 1, vertex.label.dist = 1.5,
    #      edge.arrow.size = 2, edge.label = sprintf("%d\n%0.2f", E(tmpg)$line, E(tmpg)$weight), edge.width = E(tmpg)$width)
    eqarrowPlot(tmpg, layout = layoutFunc(tmpg), edge.arrow.size=E(tmpg)$width/6,
                edge.width=E(tmpg)$width, edge.color=E(tmpg)$color, edge.label = sprintf("%d\n%0.2f", E(tmpg)$line, E(tmpg)$weight), pr = pr)
  }
  if (getResult) return(edges)
}

# for each subgraph in weight order
analyseAllSubgraphs <- function(decomp, interactive = FALSE, pr, urlTemplate = c()) {
  out <- data.frame()
  for (i in 1:length(decomp$weightOrder)) {
    if (interactive) print(paste("----  Subgraph: ", i, "  ----", sep = ""))
    out <- rbind(out, analyseSubgraph(decomp, i, interactive, TRUE, pr, urlTemplate))
    if (interactive) invisible(readline(prompt="Press [enter] to continue and esc to quit"))
  }
  if (nrow(out) > 0) out <- out[order(-out$weight),]
  rownames(out) <- NULL
  return(out)
}

# remove the sub-threshold edges from the graph for better visualisation...
trimGraph <- function(g, percentile) {
  if (!is.null(E(g)$weight)) {
    maxPressure <- max(E(g)$weight)
    threshold <- maxPressure * (1 - percentile)
    outG <- delete.edges(g, which(E(g)$weight <= threshold))
    return(addWidth(outG))
  }
  return(g)
}

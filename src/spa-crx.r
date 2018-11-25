
#### Initialise ####
rm(list=ls())
setwd("~/Documents/Projects/SPA/") # edit to suit your environment
source("./src/spa-utils.r")

loadCRX <- function() {
  Data <- read.table("./data/crx.data", header=F, sep = ",", na.strings = "?")
  names(Data) <- c("Gender", "Age", "MonthlyExpenses", "MaritalStatus", "HomeStatus", "Occupation", "BankingInstitution", "YearsEmployed", "NoPriorDefault", "Employed", "CreditScore", "DriversLicense", "AccountType", "MonthlyIncome", "AccountBalance", "Approved")
  Data$Gender <- as.factor(Data$Gender) 
  Data$Age <- as.numeric(Data$Age)
  Data$MonthlyExpenses <- as.integer(Data$MonthlyExpenses) 
  Data$MaritalStatus <- as.factor(Data$MaritalStatus) 
  Data$HomeStatus <- as.factor(Data$HomeStatus) 
  Data$Occupation <- as.factor(Data$Occupation) 
  Data$BankingInstitution <- as.factor(Data$BankingInstitution) 
  Data$YearsEmployed <- as.numeric(Data$YearsEmployed) 
  Data$NoPriorDefault <- as.factor(Data$NoPriorDefault) 
  Data$Employed <- as.factor(Data$Employed) 
  Data$CreditScore <- as.numeric(Data$CreditScore) 
  Data$DriversLicense <- as.factor(Data$DriversLicense)
  Data$AccountType <- as.factor(Data$AccountType)
  Data$MonthlyIncome <- as.integer(Data$MonthlyIncome)
  Data$AccountBalance <- as.numeric(Data$AccountBalance)
  Data$Approved <- as.factor(Data$Approved)
  
  # convert numeric columns to binned factors
  Data$Age <- n2bf(Data$Age, 10)
  Data$MonthlyExpenses <- n2bf(Data$MonthlyExpenses, 6, doubling = TRUE, asint = TRUE)
  Data$YearsEmployed <- n2bf(Data$YearsEmployed, 8, doubling = TRUE)
  Data$CreditScore <- n2bf(Data$CreditScore, 7, doubling = TRUE, asint = TRUE)
  Data$MonthlyIncome <- n2bf(Data$MonthlyIncome, 7, doubling = TRUE, asint = TRUE)
  Data$AccountBalance <- n2bf(Data$AccountBalance, 16, doubling = TRUE, asint = TRUE)
  
  # omit NAs for now but eventually have an NA category for them
  Data <- na.omit(Data)
  return(Data)
}

Data <- loadCRX()

origSymbolSet <- getSymbolSet(Data)

# standardise level names in preparation for SPA
# for (c in 1:ncol(Data)) levels(Data[,c]) <- LETTERS[1:length(levels(Data[,c]))]

symbolSet <- getSymbolSet(Data)

# focus on relevant data
dims <- c(1, 4, 5, 9, 10) # columns of interest
colnames(Data)[dims]
symSet <- symbolSet[,dims] # strip down to relevant columns
symSet <- symSet[rowSums(is.na(symSet)) != ncol(symSet), ] # strip rows with all NAs
origSymSet <- origSymbolSet[,dims] # strip down to relevant columns
origSymSet <- origSymSet[rowSums(is.na(origSymSet)) != ncol(origSymSet), ] # strip rows with all NAs

TF <- getTypeFreqs(Data, dims, symSet)
str(TF)
# TF is now equivalent to MB it is a type frequency table

# TF types sorted by prevalence
TF[order(TF$PP), ]

# Plot of the sorted spectrum of prevalence values for all Myers-Briggs types. AP = %ofPop.
sortedPlot(TF, "PP", ptsize = 3, datatype = "Types")

# Cluster Diagram
gDist <- daisy(TF, metric = "gower")
hc <- hclust(gDist)
ggdendrogram(hc)


scenarios <- getScenarios(TF, symSet, cname = "PP", nSkip = 0)

getPath(scenarios, c("1,b", "2,u", "3,g", "4,t", "5,t"), symSet)

# Plot of the sorted spectrum of group prevalence values for all adaptation scenarios. GroupAP = %ofPop
sortedPlot(scenarios, "GroupAP", datatype = "Adaptation Scenarios")

# Plot of the sorted spectrum of choice difference values for all adaptation scenarios. Diff = yin% - yang%
sortedPlot(scenarios, "Diff1", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "Diff2", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "Diff3", datatype = "Adaptation Scenarios")

# Plot of the sorted spectrum of demographic pressure values for all adaptation scenarios. DP = GroupAP * Diff 
sortedPlot(scenarios, "DP1", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "DP2", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "DP3", datatype = "Adaptation Scenarios")

# Plot of the sorted spectrum of TP values for all adaptation scenarios. TP = Diff / GroupAP
sortedPlot(scenarios, "TP1", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "TP2", datatype = "Adaptation Scenarios")
sortedPlot(scenarios, "TP3", datatype = "Adaptation Scenarios")


paths <- getAllPaths(scenarios, symSet)
str(paths)

sortedPlot(paths, "TGroupAP", lblsize = 4, datatype = "Evolutionary Paths")

# Plot of the sorted spectrum of total choice difference values for all 4 step evolutionary paths.
sortedPlot(paths, "TChDiff", lblsize = 4, datatype = "Evolutionary Paths")

# Plot of the sorted spectrum of demographic pressure values for all 4 step evolutionary paths.
sortedPlot(paths, "TChDP", lblsize = 4, datatype = "Evolutionary Paths")

# Plot of the sorted spectrum of total targeted pressure values for all 4 step evolutionary paths.
sortedPlot(paths, "TChTP", lblsize = 4, datatype = "Evolutionary Paths")

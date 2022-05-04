#  Copyright 2022 The Regents of the University of Colorado
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#  Author:    Christian Rickert <christian.rickert@cuanschutz.edu>
#  Group:     Human Immune Monitoring Shared Resource (HIMSR)
#             University of Colorado, Anschutz Medical Campus
#
#  Title:     csv-2-fcs
#  Summary:   Converts text files into flow cytometry standard files
#  Version:   1.0 (2022-05-03)
#
#  DOI:       https://doi.org/10.5281/zenodo.4741394
#  URL:       https://github.com/christianrickert/CU-HIMSR/
#
#  Description:
#
#  csv-2-fcs is an R script for RStudio that converts text files with
#  various delimiters (*.csv, *.txt) into flow cytometry standard files
#  (*.fcs) based on the the FCS 3.0 specifications using 'flowCore'.
#  The script can specifically include and/or exclude user-specified
#  columns and will remove all non-numeric columns before exporting.
#  Special characters in numeric columns will be replaced with zeros.
#  While the script aims at minimizing its memory footprint and, please
#  keep in mind that it will use approximately two times the input data
#  size from your system memory, depending on your selected input data.
#  Furthermore, performance will also depend on your data input source
#  (SSD > HDD > network) and your operating system: MacOS is using only
#  a single-threaded version of 'data.table' by default. However, a
#  multi-threaded version can be installed manually:
#  [https://github.com/Rdatatable/data.table/wiki/Installation]
#     Copy the script to your target location and run it for first time
#  to create an 'import' and an 'export' folder. Then place your text
#  files into the 'import' folder and confirm the script's variables.
#  Finally, run the script to batch-process your files.
#  If you activate the 'revertResult' variable by setting it to TRUE,
#  the script will convert the FCS export files back into CSV files -
#  so you can easily check the quality of the conversion.
#     This script is a complete redesign and rewrite inspired by
#  Thomas Hurst's "CSV-to-FCS" and "FCS-to-CSV" repository scripts,
#  [https://github.com/sydneycytometry/CSV-to-FCS]
#  which were in turn adapted from Yann Abraham's "createFlowFram"script
#  [https://gist.github.com/yannabraham/c1f9de9b23fb94105ca5].

#
#  Packages
#

if(!require('data.table')) {install.packages('data.table')}
if(!require('rstudioapi')) {install.packages('rstudioapi')}
if(!requireNamespace("BiocManager", quietly = TRUE)) {
  install.packages("BiocManager", quiet = TRUE)
}
if(!require('flowCore')) {BiocManager::install("flowCore", update = FALSE)}

#
#  Functions
#

# function to immediately print out a string
catflush <- function(string) {
  cat(string)
  flush.console
}

#
#  Variables
#

# set input and output variables
currentFolder   <- dirname(rstudioapi::getSourceEditorContext()$path)  # script location
importFolder    <- file.path(currentFolder, "import", fsep = .Platform$file.sep)  # relative path
importPattern   <- "\\.csv$|\\.txt$"  # file extension expression (case-insensitive)
importSeparator <- "auto"  # separator with highest row-consistent split count is used
includeColumns  <- c()  # include columns, exclusively, by name before export (case-sensitive)
excludeColumns  <- c()  # exclude columns by name before export (case-sensitive)
exportFolder    <- file.path(currentFolder, "export", fsep = .Platform$file.sep)
exportPrecision <- "double"  # any of "integer", "numeric", "double"
replaceNA       <- TRUE  # replace NA in numeric columns with 0 before export
revertResult    <- FALSE  # convert the result file back into a csv file

#
#  Main program
#

# set up working directories
if (!file.exists(importFolder)) {dir.create(importFolder)}
print(paste("Input folder:", importFolder))
if (!file.exists(exportFolder)) {dir.create(exportFolder)}
print(paste("Export folder:", exportFolder))

# get list of input files
importFileNames <- list.files(path = importFolder,
                              pattern = importPattern,
                              ignore.case = TRUE)

# read data from CSV and write FCS data
count <- 1
importFileNamesLength <- length(importFileNames)
for (importFile in importFileNames) {
  catflush(paste("\nFile: ", count, "/", importFileNamesLength, "\n", sep = ""))
  catflush(paste("  Import:", importFile, "\n"))

  # read file data as data table
  setwd(importFolder)
  catflush(paste("    Reading...\n"))
  fileData <- fread(file = importFile,
                    nThread = getDTthreads(),
                    sep = importSeparator,
                    verbose = FALSE)
  catflush(paste("    done\n"))

  # convert data table columns to numeric, if user-specified, else mark for deletion
  deleteColumns <- c()
  if (length(includeColumns) > 0) {
    as.numeric(names(fileData) %in% includeColumns)
    deleteColumns <- names(fileData)[!names(fileData) %in% includeColumns]
  }

  # filter data table by column names, optional (by-reference operation, fast)
  removeColumns <- c()
  if (length(deleteColumns) > 0 || length(excludeColumns) > 0) {
    removeColumns <- union(deleteColumns, excludeColumns)
  }
  if (length(removeColumns) > 0) {
    catflush(paste("    Filtering... "))
    fileData[, (removeColumns) := NULL]
    catflush(paste("done\n"))
  }

  # filter data table by columns with non-numeric values, mandatory
  catflush(paste("    Checking... "))
  nonNumericColumns <- names(which(sapply(fileData, Negate(is.numeric))))
  if (length(nonNumericColumns) > 0) {fileData[, (nonNumericColumns) := NULL]}
  catflush(paste("done\n"))

  # replace NA and #N/A values in numeric columns with zero (in-place, but very slow)
  if (replaceNA == TRUE) {
    catflush(paste("    Replacing... "))
    zero <- 0.0
    if(exportPrecision == "integer") {zero <- 0}
    columns <- seq_along(fileData)
    for (c in columns) {
      set(fileData,
          i = which(is.na(fileData[[c]])),
          j = c,
          value = zero)
    }
    catflush(paste("done\n"))
  }

  # create flow frame from data table (copy operation, slow)
  catflush(paste("    Converting... "))
  flowData <- new("flowFrame", exprs = as.matrix(fileData))
  catflush(paste("done\n"))
  remove(fileData)

  # write flow frame into flow file
  setwd(exportFolder)
  exportFile = paste(sub(importPattern, "", importFile), ".fcs", sep = "")
  catflush(paste("  Export:", exportFile, " (FCS 3.0)\n"))
  catflush(paste("    Writing... "))
  write.FCS(flowData,
            exportFile,
            what = exportPrecision,
            delimiter = "|",
            endian = "big")
  catflush(paste("done\n"))
  remove(flowData)

  if (revertResult == TRUE && isFCSfile(exportFile) == TRUE) {
    revertFile = paste(sub("\\.fcs$", "", exportFile), ".csv", sep = "")
    catflush(paste("  Revert:", revertFile, "\n"))

    # read new flow frame from flow file
    catflush(paste("    Reading... "))
    flowData <- read.FCS(exportFile,
                         transformation = FALSE)
    catflush(paste("done\n"))

    # convert flow frame into data table
    catflush(paste("    Converting... "))
    flowTable <- exprs(flowData)
    catflush(paste("done\n"))
    remove(flowData)

    # write data table into data file
    catflush(paste("    Writing... "))
    write.csv(flowTable,
              revertFile)
    catflush(paste("done\n"))
    remove(flowTable)
  }

  count <- count + 1
}

# Clearing R environment
rm(list=ls())

# Run complete
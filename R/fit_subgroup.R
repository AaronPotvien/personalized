
#' Fitting subgroup identification models
#'
#' @description Fits subgroup identification model class of Chen, et al (2017)
#'
#' @param x The design matrix (not including intercept term)
#' @param y The response vector
#' @param trt treatment vector with each element equal to a 0 or a 1, with 1 indicating
#'            treatment status is active.
#' @param propensity.func function that inputs the design matrix x and the treatment vector trt and outputs
#' the propensity score, ie Pr(trt = 1 | X = x). Function should take two arguments 1) x and 2) trt. See example below.
#' For a randomized controlled trial this can simply be a function that returns a constant equal to the proportion
#' of patients assigned to the treatment group, i.e.:
#' \code{propensity.func = function(x, trt) 0.5}.
#' @param loss choice of both the M function from Chen, et al (2017) and potentially the penalty used for variable selection.
#' All \code{loss} options starting with \code{sq_loss} use M(y, v) = (v - y) ^ 2, all options starting with \code{logistic_loss} use
#' the logistic loss: M(y, v) = y * log(1 + exp\{-v\}), and all options starting with \code{cox_loss} use the negative partial likelihood loss for the Cox PH model.
#' All options ending with \code{lasso} have a lasso penalty added to the loss for variable selection. \code{sq_loss_lasso_gam}
#' and \code{logistic_loss_lasso_gam} first use the lasso to select variables and then fit a generalized additive model
#' with nonparametric additive terms for each selected variable. \code{sq_loss_gam} involves a squared error loss with a generalized additive model and no variable selection.
#' \code{sq_loss_gbm} involves a squared error loss with a gradient-boosted decision trees model for the benefit score; this
#' allows for flexible estimation using machine learning and can be useful when the underlying treatment-covariate interaction
#' is complex.
#' \itemize{
#'     \item{\code{"sq_loss_lasso"}}{ - M(y, v) = (v - y) ^ 2 with linear model and lasso penalty}
#'     \item{\code{"logistic_loss_lasso"}}{ - M(y, v) = -[yv - log(1 + exp\{-v\})] with with linear model and lasso penalty}
#'     \item{\code{"cox_loss_lasso"}}{ - M corresponds to the negative partial likelihood of the cox model with linear model and additionally a lasso penalty}
#'     \item{\code{"sq_loss_lasso_gam"}}{ - M(y, v) = (v - y) ^ 2 with variables selected by lasso penalty and generalized additive model fit on the selected variables}
#'     \item{\code{"logistic_loss_lasso_gam"}}{ - M(y, v) = y * log(1 + exp\{-v\}) with variables selected by lasso penalty and generalized additive model fit on the selected variables}
#'     \item{\code{"sq_loss_gam"}}{ - M(y, v) = (v - y) ^ 2 with generalized additive model fit on all variables}
#'     \item{\code{"logistic_loss_gam"}}{ - M(y, v) = y * log(1 + exp\{-v\}) with generalized additive model fit on all variables}
#'     \item{\code{"sq_loss_gbm"}}{ - M(y, v) = (v - y) ^ 2 with gradient-boosted decision trees model}
#'     \item{\code{"abs_loss_gbm"}}{ - M(y, v) = |v - y| with gradient-boosted decision trees model}
#'     \item{\code{"logistic_loss_gbm"}}{ - M(y, v) = -[yv - log(1 + exp\{-v\})] with gradient-boosted decision trees model}
#'     \item{\code{"cox_loss_gbm"}}{ - M corresponds to the negative partial likelihood of the cox model with gradient-boosted decision trees model}
#' }
#' @param method subgroup ID model type. Either the weighting or A-learning method of Chen et al, (2017)
#' @param augment.func function which inputs the response \code{y}, the covariates \code{x}, and \code{trt} and outputs
#' predicted values for the response using a model constructed with \code{x}. \code{augment.func()} can also be simply
#' a function of \code{x} and \code{y}. This function is used for efficiency augmentation.
#' When the form of the augmentation function is correct, it can provide efficient estimation of the subgroups
#' Example 1: \code{augment.func <- function(x, y) {lmod <- lm(y ~ x); return(fitted(lmod))}}
#'
#' Example 2: \code{augment.func <- function(x, y, trt) {lmod <- lm(y ~ x + trt); return(fitted(lmod))}}
#' @param cutpoint numeric value for patients with benefit scores above which
#' (or below which if \code{larger.outcome.better = FALSE})
#' will be recommended to be in the treatment group
#' @param larger.outcome.better boolean value of whether a larger outcome is better/preferable. Set to \code{TRUE}
#' if a larger outcome is better/preferable and set to \code{FALSE} if a smaller outcome is better/preferable. Defaults to \code{TRUE}.
#' @param reference.trt which treatment should be treated as the reference treatment. Defaults to the first level of \code{trt}
#' if \code{trt} is a factor or the first alphabetical or numerically first treatment level.
#' @param retcall boolean value. if \code{TRUE} then the passed arguments will be saved. Do not set to \code{FALSE}
#' if the \code{validate.subgroup()} function will later be used for your fitted subgroup model. Only set to \code{FALSE}
#' if memory is limited as setting to \code{TRUE} saves the design matrix to the fitted object
#' @param ... options to be passed to underlying fitting function. For all \code{loss} options with \code{lasso},
#' this will be passed to \code{cv.glmnet} and for all \code{loss} options with \code{mcp} this will be passed
#' to \code{cv.ncvreg}. Note that for all \code{loss} options that use \code{gam()} from the \code{mgcv} package,
#' the user cannot supply the \code{gam} argument \code{method} because it is also an argument of \code{fit.subgroup}, so
#' instead, to change the \code{gam method} argument, supply \code{method.gam}, ie \code{method.gam = "REML"}.
#' @seealso \code{\link[personalized]{validate.subgroup}} for function which creates validation results for subgroup
#' identification models, \code{\link[personalized]{predict.subgroup_fitted}} for a prediction function for fitted models
#' from \code{fit.subgroup}, \code{\link[personalized]{plot.subgroup_fitted}} for a function which plots
#' results from fitted models, and \code{\link[personalized]{print.subgroup_fitted}}
#' for arguments for printing options for \code{fit.subgroup()}.
#' from \code{fit.subgroup}.
#' @references Chen, S., Tian, L., Cai, T. and Yu, M. (2017), A general statistical framework for subgroup identification
#' and comparative treatment scoring. Biometrics. doi:10.1111/biom.12676 \url{http://onlinelibrary.wiley.com/doi/10.1111/biom.12676/abstract}
#'
#' @examples
#' library(personalized)
#'
#' set.seed(123)
#' n.obs  <- 1000
#' n.vars <- 50
#' x <- matrix(rnorm(n.obs * n.vars, sd = 3), n.obs, n.vars)
#'
#'
#' # simulate non-randomized treatment
#' xbetat   <- 0.5 + 0.5 * x[,21] - 0.5 * x[,41]
#' trt.prob <- exp(xbetat) / (1 + exp(xbetat))
#' trt01    <- rbinom(n.obs, 1, prob = trt.prob)
#'
#' trt      <- 2 * trt01 - 1
#'
#' # simulate response
#' delta <- 2 * (0.5 + x[,2] - x[,3] - x[,11] + x[,1] * x[,12] )
#' xbeta <- x[,1] + x[,11] - 2 * x[,12]^2 + x[,13] + 0.5 * x[,15] ^ 2
#' xbeta <- xbeta + delta * trt
#'
#' # continuous outcomes
#' y <- drop(xbeta) + rnorm(n.obs, sd = 2)
#'
#' # binary outcomes
#' y.binary <- 1 * (xbeta + rnorm(n.obs, sd = 2) > 0 )
#'
#' # time-to-event outcomes
#' surv.time <- exp(-20 - xbeta + rnorm(n.obs, sd = 1))
#' cens.time <- exp(rnorm(n.obs, sd = 3))
#' y.time.to.event  <- pmin(surv.time, cens.time)
#' status           <- 1 * (surv.time <= cens.time)
#'
#' # create function for fitting propensity score model
#' prop.func <- function(x, trt)
#' {
#'     # fit propensity score model
#'     propens.model <- cv.glmnet(y = trt,
#'                                x = x, family = "binomial")
#'     pi.x <- predict(propens.model, s = "lambda.min",
#'                     newx = x, type = "response")[,1]
#'     pi.x
#' }
#'
#' subgrp.model <- fit.subgroup(x = x, y = y,
#'                            trt = trt01,
#'                            propensity.func = prop.func,
#'                            loss   = "sq_loss_lasso",
#'                            nfolds = 5)              # option for cv.glmnet
#'
#' summary(subgrp.model)
#'
#' # fit lasso + gam model with REML option for gam
#'
#' subgrp.modelg <- fit.subgroup(x = x, y = y,
#'                             trt = trt01,
#'                             propensity.func = prop.func,
#'                             loss   = "sq_loss_lasso_gam",
#'                             method.gam = "REML",     # option for gam
#'                             nfolds = 5)              # option for cv.glmnet
#'
#' subgrp.modelg
#'
#' subgrp.model.bin <- fit.subgroup(x = x, y = y.binary,
#'                            trt = trt01,
#'                            propensity.func = prop.func,
#'                            loss   = "logistic_loss_lasso",
#'                            type.measure = "auc",    # option for cv.glmnet
#'                            nfolds = 5)              # option for cv.glmnet
#'
#' subgrp.model.bin
#'
#' library(survival)
#' subgrp.model.cox <- fit.subgroup(x = x, y = Surv(y.time.to.event, status),
#'                            trt = trt01,
#'                            propensity.func = prop.func,
#'                            loss   = "cox_loss_lasso",
#'                            nfolds = 5)              # option for cv.glmnet
#'
#' subgrp.model.cox
#'
#'
#' @export
fit.subgroup <- function(x,
                         y,
                         trt,
                         propensity.func = NULL,
                         loss       = c("sq_loss_lasso",
                                        "logistic_loss_lasso",
                                        "cox_loss_lasso",
                                        "sq_loss_lasso_gam",
                                        "logistic_loss_lasso_gam",
                                        "sq_loss_gam",
                                        "logistic_loss_gam",
                                        "sq_loss_gbm",
                                        "abs_loss_gbm",
                                        "logistic_loss_gbm",
                                        "cox_loss_gbm"),
                         method     = c("weighting", "a_learning"),
                         augment.func = NULL,
                         cutpoint   = 0,
                         larger.outcome.better = TRUE,
                         reference.trt = NULL,
                         retcall    = TRUE,
                         ...)
{

    loss   <- match.arg(loss)
    method <- match.arg(method)


    # make sure outcome is consistent with
    # other options selected if there is any
    # indication of a survival outcome or model
    if ( xor(class(y) == "Surv", grepl("cox_loss", loss)) )
    {
        ifelse(
            grepl("cox_loss", loss),
            stop("Must provide 'Surv' object if loss/family corresponds to a Cox model. See\n
                 '?Surv' for more information about 'Surv' objects."),
            stop("Loss and family must correspond to a Cox model for time-to-event outcomes.")
        )
    }

    if (grepl("cox_loss", loss))
    {
        family <- "cox"
    } else if (grepl("logistic_loss", loss) | grepl("huberized_loss", loss))
    {
        family <- "binomial"
    } else
    {
        family <- "gaussian"
    }


    dims   <- dim(x)
    if (is.null(dims)) stop("x must be a matrix object.")

    y      <- drop(y)
    vnames <- colnames(x)

    # set variable names if they are not set
    if (is.null(vnames)) vnames <- paste0("V", 1:dims[2])

    ## will be a flag for later use if
    ## I decide to make outcome-weighted learning
    ## (ie flipping loss) an option
    outcome.weighted <- FALSE




    # check to make sure arguments of augment.func are correct
    if (!is.null(augment.func))
    {
        augmentfunc.names <- sort(names(formals(augment.func)))
        if (length(augmentfunc.names) == 3)
        {
            if (any(augmentfunc.names != c("trt", "x", "y")))
            {
                stop("arguments of augment.func() should be 'trt', 'x', and 'y'")
            }
        } else if (length(augmentfunc.names) == 2)
        {
            if (any(augmentfunc.names != c("x", "y")))
            {
                stop("arguments of augment.func() should be 'x' and 'y'")
            }
            augment.func2 <- augment.func
            augment.func  <- function(trt, x, y) augment.func2(x = x, y = y)
        } else
        {
            stop("augment.func() should only have either two arguments: 'x' and 'y', or three arguments:
                 'trt', 'x', and 'y'")
        }
    }

    if (is.factor(trt))
    {
        # drop any unused levels of trt
        trt         <- droplevels(trt)
        unique.trts <- levels(trt)
        n.trts      <- length(unique.trts)
    } else
    {
        unique.trts <- sort(unique(trt))
        n.trts      <- length(unique.trts)
    }

    if (n.trts < 2)           stop("trt must have at least 2 distinct levels")
    if (n.trts > dims[1] / 3) stop("trt must have no more than n.obs / 3 distinct levels")

    if (!is.null(reference.trt))
    {
        if (!(reference.trt %in% unique.trts))
        {
            stop("reference.trt must be one of the treatment levels")
        }

        reference.idx   <- which(unique.trts == reference.trt)
        comparison.idx  <- (1:n.trts)[-reference.idx]
        comparison.trts <- unique.trts[-reference.idx]

    } else
    {
        reference.idx   <- 1L
        comparison.idx  <- (1:n.trts)[-reference.idx]
        comparison.trts <- unique.trts[-reference.idx]
        reference.trt   <- unique.trts[reference.idx]
    }

    if (n.trts > 2 & (grepl("_gbm", loss) | grepl("_gam", loss)) )
    {
        stop("gbm and gam based losses not supported for multiple treatments (number of total treatments > 2)")
    }

    # defaults to constant propensity score within trt levels
    # the user will almost certainly want to change this
    if (is.null(propensity.func))
    {
        if (n.trts == 2)
        {
            mean.trt <- mean(trt == unique.trts[2L])
            propensity.func <- function(trt, x) rep(mean.trt, length(trt))
        } else
        {
            mean.trt <- numeric(n.trts)
            for (t in 1:n.trts)
            {
                mean.trt[t] <- mean(trt == unique.trts[t])
            }
            propensity.func <- function(trt, x)
            {
                pi.x <- numeric(length(trt))
                for (t in 1:n.trts)
                {
                    which.t       <- trt == unique.trts[t]
                    pi.x[which.t] <- mean(which.t)
                }

                pi.x
            }
        }
    }


    # check to make sure arguments of augment.func are correct
    if (family == "gaussian" & !is.null(augment.func))
    {
        B.x   <- unname(drop(augment.func(trt = trt, x = x, y = y)))

        if (NROW(B.x) != NROW(y))
        {
            stop("augment.func() should return the same number of predictions as observations in y")
        }

        y.adj <- y - B.x
    } else
    {
        y.adj <- y
    }

    # stop if augmentation function provided
    # for non-gaussian outcomes.
    # has not been developed yet
    if (!is.null(augment.func) & family != "gaussian")
    {
        warning("Efficiency augmentation not available for non-continuous outcomes yet. No augmentation applied.")
    }

    larger.outcome.better <- as.logical(larger.outcome.better[1])
    retcall               <- as.logical(retcall[1])

    # save the passed arguments for later use in validate.subgroupu()
    # and plot.subgroup_fitted() functions
    if (retcall)
    {
        this.call     <- mget(names(formals()), sys.frame(sys.nframe()))

        this.call$... <- NULL
        this.call     <- c(this.call, list(...))
    } else
    {
        this.call     <- NULL
    }

    # check to make sure arguments of propensity.func are correct
    propfunc.names <- sort(names(formals(propensity.func)))
    if (length(propfunc.names) == 2)
    {
        if (any(propfunc.names != c("trt", "x")))
        {
            stop("arguments of propensity.func() should be 'x' and 'trt'")
        }
    } else
    {
        stop("propensity.func() should only have two arguments: 'trt' and 'x'")
    }

    # compute propensity scores
    pi.x   <- propensity.func(x = x, trt = trt)

    # make sure the resulting propensity scores are in the
    # acceptable range (ie 0-1)
    rng.pi <- range(pi.x)

    if (rng.pi[1] <= 0 | rng.pi[2] >= 1) stop("propensity.func() should return values between 0 and 1")

    # construct design matrix to be passed to fitting function
    x.tilde <- create.design.matrix(x             = x,
                                    pi.x          = pi.x,
                                    trt           = trt,
                                    method        = method,
                                    reference.trt = reference.trt)

    # construct observation weight vector
    wts     <- create.weights(pi.x   = pi.x,
                              trt    = trt,
                              method = method)

    if (n.trts > 2)
    {
        all.cnames <- numeric(ncol(x.tilde))
        len.names  <- length(vnames) + 1
        for (tr in 1:(n.trts - 1))
        {
            idx.cur <- ((len.names * (tr - 1)) + 1):(len.names * tr)
            all.cnames[idx.cur] <- c( comparison.trts[tr],
                                      paste(vnames, 1:(n.trts - 1), sep = ".") )
        }
    } else
    {
        all.cnames <- c( comparison.trts,
                         vnames )
    }

    colnames(x.tilde) <- all.cnames

    # identify correct fitting function and call it
    fit_fun      <- paste0("fit_", loss)
    fitted.model <- do.call(fit_fun, list(x = x.tilde, trt = trt, n.trts = n.trts,
                                          y = y.adj, wts = wts, family = family, ...))


    # save extra results
    fitted.model$call                  <- this.call
    fitted.model$family                <- family
    fitted.model$loss                  <- loss
    fitted.model$method                <- method
    fitted.model$larger.outcome.better <- larger.outcome.better
    fitted.model$var.names             <- vnames
    fitted.model$n.trts                <- n.trts
    fitted.model$comparison.trts       <- comparison.trts
    fitted.model$reference.trt         <- reference.trt

    fitted.model$benefit.scores        <- fitted.model$predict(x)

    fitted.model$recommended.trts      <- predict.subgroup_fitted(fitted.model, newx = x,
                                                                  type = "trt.group",
                                                                  cutpoint = cutpoint)

    # calculate sizes of subgroups and the
    # subgroup treatment effects based on the
    # benefit scores and specified benefit score cutpoint
    fitted.model$subgroup.trt.effects <- subgroup.effects(fitted.model$benefit.scores,
                                                          y, trt, cutpoint,
                                                          larger.outcome.better,
                                                          reference.trt = reference.trt)

    class(fitted.model) <- "subgroup_fitted"

    fitted.model
}

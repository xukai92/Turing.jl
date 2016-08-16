##############################
# Demo - Univariate Gaussian #
##############################
using Turing, Distributions, DualNumbers
# using Gadfly

# Generate synthesised data
data_num = 25
xs = rand(Normal(0.5, 1), data_num)

# ML estimates
m_ml = sum(xs) / data_num
s_ml = sqrt(sum((xs - m_ml)'*(xs - m_ml)) / data_num)

# Define model
@model unigauss begin
  @assume s ~ InverseGamma(2, 3)
  @assume m ~ Normal(0, sqrt(s))
  for x in xs
    @observe x ~ Normal(m, sqrt(s))
  end
  @predict s m
end

# Run the sampler
chain = sample(unigauss, HMC(2000, 0.01, 25))
m = mean([d[:m] for d in chain[:samples]])
s = sqrt(mean([d[:s] for d in chain[:samples]]))

# Effective Sample Size
samples_m = [Float64(realpart(d[:m])) for d in chain[:samples]]
Turing.ess(samples_m)

# KL plot
function kl(p_μ, p_σ, q_μ, q_σ)
  return (log(q_σ / p_σ) + (p_σ^2 + (p_μ - q_μ)^2) / (2 * q_σ^2) - 0.5)
end

kls = [kl(0.5, 1, Float64(realpart(d[:m])), Float64(realpart(d[:s]))) for d in chain[:samples]]

kls_plot = plot(x=1:length(kls), y=kls, Geom.line, Guide.xlabel("KL Divergence"), Guide.ylabel("Iterations"),Guide.title("KL Divergence as a Function of Iterations"))

draw(PNG("/Users/kai/Turing/docs/demo/unigausskls.png", 6inch, 5.5inch), kls_plot)

# Trace
ms = [Float64(realpart(d[:m])) for d in chain[:samples]]
ss = [Float64(realpart(d[:s])) for d in chain[:samples]]

ms_layer = layer(x=1:length(ms), y=ms, Geom.line, Geom.smooth, Theme(default_color=colorant"red"))
ss_layer = layer(x=1:length(ss), y=ss, Geom.line, Geom.smooth, Theme(default_color=colorant"green"))
trace_plot = plot(ms_layer, ss_layer, Guide.xlabel("Value"), Guide.ylabel("Iterations"),Guide.title("Evoluation of mean and variance as a Function of Iterations"), Guide.manual_color_key("Legend", ["mean", "variance"], ["red", "green"]))

draw(PNG("/Users/kai/Turing/docs/demo/unigausstrace.png", 6inch, 5.5inch), trace_plot)

# Validation
chain2 = sample(unigauss, PG(20, 30))



################################
# Demo - Multivariate Gaussian #
################################
using Turing, Distributions, DualNumbers, PDMats

# Generate synthesised data
xs = rand(MvNormal(Vector{Float64}([1, 1]),
                   PDMat(Array{Float64,2}([1 0; 0 1]))),
          50)

# Define model
@model multigauss begin
  @assume m ~ MvNormal([1, 1], [4 0; 0 4])
  for x in xs
    @observe x ~ MvNormal(m, [1 0; 0 1])
  end
  @predict m
end

# Run the sampler
chain = sample(multigauss, HMC(100, 0.05, 5))
m = mean([Vector{Float64}(realpart(d[:m]))for d in chain[:samples]])

# ML estimate
m_ml = [mean(xs[1,:]), mean(xs[2,:])]



####################################################
# Demo - Bayesian Neural Nets with a Single Neuron #
####################################################
using Turing, Distributions, DualNumbers, Gadfly, ForwardDiff

# Helper function for the single neuron bnn
function singley(x, w0, w1, w2)
  return 1 / (1 + exp(-(w0 + w1 * x[1] + w2 * x[2])))
end

# Training data
xs = Array[[1, 2], [2, 1], [-2, -1], [-1, -2]]
ts = [1, 1, 0, 0]

# Define the model
α = 0.25          # regularizatin term
σ = sqrt(1 / α)   # variance of the Gaussian prior
@model singlebnn begin
  @assume w0 ~ Normal(0, σ)
  @assume w1 ~ Normal(0, σ)
  @assume w2 ~ Normal(0, σ)
  for i = 1:4
    y = singley(xs[i], w0, w1, w2)
    @observe ts[i] ~ Bernoulli(y)
  end
  @predict w0 w1 w2
end

# Sample the model
chain = sample(singlebnn, HMC(3000, 0.1, 2))

# Helper function for predicting
function singlepredict(x, chain)
  n = length(chain[:w0])
  w0s = chain[:w0]
  w1s = chain[:w1]
  w2s = chain[:w2]
  return mean([singley(x, w0s[i], w1s[i], w2s[i]) for i in 1:n])
end

# Compute predctions
y = Float64[singlepredict(xs[i], chain) for i = 1:4]

# Gradient descend
function G(args::Vector)
  w0, w1, w2 = args[1], args[2], args[3]
  error = 0
  for i = 1:4
    y = singley(xs[i], w0, w1, w2)
    error -= ts[i] * log2(y) + (1 - ts[i]) * log(1 - y)
  end
  return error + α * 0.5 * (w0^2 + w1^2 + w2^2)
end

∇G = x -> ForwardDiff.gradient(G, x)

w0g, w1g, w2g = randn(), randn(), randn()

println("Initial loss: ", G([w0g, w1g, w2g]))

iteration_num = 3000
chaing = Array{Dict{Symbol, Any}}(iteration_num)
l_rate = 0.1
for i = 1:iteration_num
  dw = ∇G([w0g, w1g, w2g])
  w0g -= l_rate * dw[1]
  w1g -= l_rate * dw[2]
  w2g -= l_rate * dw[3]
  chaing[i] = Dict{Symbol, Any}(:w0=>w0g, :w1=>w1g, :w2=>w2g)
end

println("Final loss: ", G([w0g, w1g, w2g]))

yg = Float64[singley(xs[i], w0g, w1g, w2g) for i = 1:4]

# Plot predictions
singledata_layer_1 = layer(x=Float64[1, 2], y=Float64[2, 1], Geom.point, Theme(default_color=colorant"red"))
singledata_layer_2 = layer(x=Float64[-1, -2], y=Float64[-2, -1], Geom.point, Theme(default_color=colorant"blue"))
singlepredictions_layer = layer(z=(x,y) -> singlepredict([x, y], chain), x=linspace(-4,4,25), y=linspace(-4,4,25), Geom.contour)
gdpredictions_layer = layer(z=(x,y) -> singley([x, y], w0g, w1g, w2g), x=linspace(-4,4,25), y=linspace(-4,4,25), Geom.contour(levels=1))

singlepredictions_plot = plot(singledata_layer_1, singledata_layer_2, singlepredictions_layer, gdpredictions_layer, Guide.xlabel("dim 1"), Guide.ylabel("dim 2"), Coord.cartesian(xmin=-4, xmax=4, ymin=-4, ymax=4))
# ,Guide.title("Predictions of the Single Neuron BNN")
# Output plot
draw(PDF("/Users/kai/Turing/docs/report/singlebnn.pdf", 5.5inch, 5inch), singlepredictions_plot)

# Trace
w0s = [Float64(realpart(d[:w0])) for d in chain[:samples]]
w1s = [Float64(realpart(d[:w1])) for d in chain[:samples]]
w2s = [Float64(realpart(d[:w2])) for d in chain[:samples]]
w0gs = [Float64(d[:w0]) for d in chaing]
w1gs = [Float64(d[:w1]) for d in chaing]
w2gs = [Float64(d[:w2]) for d in chaing]
chaing

w0s_layer = layer(x=1:length(w0s), y=w0s, Geom.line, Theme(default_color=colorant"red"))
w1s_layer = layer(x=1:length(w1s), y=w1s, Geom.line, Theme(default_color=colorant"green"))
w2s_layer = layer(x=1:length(w2s), y=w2s, Geom.line, Theme(default_color=colorant"blue"))
w0gs_layer = layer(x=1:length(w0gs), y=w0gs, Geom.line, Theme(default_color=colorant"red"))
w1gs_layer = layer(x=1:length(w1gs), y=w1gs, Geom.line, Theme(default_color=colorant"green"))
w2gs_layer = layer(x=1:length(w2gs), y=w2gs, Geom.line, Theme(default_color=colorant"blue"))

single_trace_plot = plot(w0s_layer, w1s_layer, w2s_layer, w0gs_layer, w1gs_layer, w2gs_layer, Guide.xlabel("Value"), Guide.ylabel("Iterations"), Guide.title("Evoluation of weights as a Function of Iterations"), Guide.manual_color_key("Legend", ["w0", "w1", "w2"], ["red", "green", "blue"]))

draw(PNG("/Users/kai/Turing/docs/demo/singletrace.png", 6inch, 5.5inch), single_trace_plot)

# Evolution in sapce
space_w = layer(x=w1s, y=w2s, Geom.point, Theme(default_color=colorant"blue", default_point_size=(0.4mm)))
space_wg = layer(x=w1gs, y=w2gs, Geom.path, Theme(default_color=colorant"red"))
single_space_plot = plot(space_wg, space_w, Guide.xlabel("w1"), Guide.ylabel("w2"),Guide.title("Evoluation of w1 and w2 in Space as a Function of Iterations"), Coord.cartesian(xmin=-5, xmax=5, ymin=-2.5, ymax=7.5), Guide.manual_color_key("Legend", ["Bayes", "GD"], ["blue", "red"]))

draw(PNG("/Users/kai/Turing/docs/demo/singlespace.png", 6inch, 5.5inch), single_space_plot)

# Loss plot
loss_bayes = Float64[G([d[:w0], d[:w1], d[:w2]]) for d in chain[:samples]]
loss_gard = Float64[G([d[:w0], d[:w1], d[:w2]]) for d in chaing]

lossb_layer = layer(x=1:length(loss_bayes), y=loss_bayes, Geom.line, Theme(default_color=colorant"blue"))
lossg_layer = layer(x=1:length(loss_gard), y=loss_gard, Geom.line, Theme(default_color=colorant"red"))
loss_plot = plot(lossb_layer, lossg_layer, Guide.xlabel("Loss"), Guide.ylabel("Iterations"), Guide.title("Loss G as a Function of Iterations"), Guide.manual_color_key("Legend", ["Bayes", "GD"], ["blue", "red"]))

# TODO: ess









###################################################
# Demo - Bayesian Neural Nets with 1 Hidden Layer #
####################################################
using Turing, Distributions, DualNumbers, Gadfly

# Activation function
function sigmoid(a)
  1 / (1 + exp(-a))
end

# NN with 1 hidden layer
function hiddeny(x, w11, w12, w2)
  x1 = [1; x]
  x2 = [1; sigmoid((w11' * x1)[1]); sigmoid((w12' * x1)[1])]
  y = sigmoid((w2' * x2)[1])
end

# Training data
xs = Array[[0, 0], [0, 1], [1, 0], [1, 1]]
ts = [0, 1, 1, 0]

# Define the model
α = 0.09          # regularizatin term
σ = sqrt(1 / α)   # variance of the Gaussian prior
mu = [0, 0, 0]
Σ = [σ 0 0; 0 σ 0; 0 0 σ]
@model hiddenbnn begin
  @assume w11 ~ MvNormal(mu, Σ)
  @assume w12 ~ MvNormal(mu, Σ)
  @assume w2 ~ MvNormal(mu, Σ)
  for i in 1:4
    y = hiddeny(xs[i], w11, w12, w2)
    @observe ts[i] ~ Bernoulli(y)
  end
  @predict w11 w12 w2
end

# Sample the model
chain = sample(hiddenbnn, HMC(1000, 0.5, 15))

# Helper function for predicting
function hiddenpredict(x, chain)
  return mean([hiddeny(x, d[:w11], d[:w12], d[:w2]) for d in chain.value])
end

# Compute predctions
y = Float64[hiddenpredict(xs[i], chain) for i = 1:4]

hidden_predictions_layer = layer(z=(x,y) -> hiddenpredict([x, y], chain), x=linspace(-4,4,25), y=linspace(-4,4,25), Geom.contour)
plot(hidden_predictions_layer)

# Demo Bernoulli in Stan
using Turing, Distributions, DualNumbers, Gadfly

xs = Float64[0, 1, 0, 1, 0, 0, 0, 0, 0, 1]

@model bernoullistanmodel begin
  @assume Θ ~ Beta(1, 1)
  for x in xs
    @observe x ~ Bernoulli(Θ)
  end
  @predict Θ
end

chain = sample(bernoullistanmodel, HMC(3000, 0.02, 2))

Θs = [Float64(realpart(d[:Θ])) for d in chain[:samples]]
Θ_mean = mean(Θs)
Θ_sd = var(Θs)

##########################
# Demo - Priors in Array #
##########################
using Turing, Distributions, DualNumbers, Gadfly

# Generate synthesised data
xs = rand(Normal(0.5, 1), 500)

# Define model
@model priorsinarray begin
  priors = Vector{Dual}(zeros(2))
  @assume priors[1] ~ InverseGamma(2, 3)
  @assume priors[2] ~ Normal(0, sqrt(priors[1]))
  for x in xs
    @observe x ~ Normal(priors[2], sqrt(priors[1]))
  end
  @predict priors
end

chain = sample(priorsinarray, HMC(1000, 0.01, 10))
priors = mean([d[:priors] for d in chain[:samples]])

############################
# Demo - Priors in Array 2 #
############################
using Turing, Distributions, DualNumbers, Gadfly, ForwardDiff

# Helper function for the single neuron bnn
function singley(x, w0, w1, w2)
  return 1 / (1 + exp(-(w0 + w1 * x[1] + w2 * x[2])))
end

# Training data
xs = Array[[1, 2], [2, 1], [-2, -1], [-1, -2]]
ts = [1, 1, 0, 0]

# Define the model
α = 0.25          # regularizatin term
σ = sqrt(1 / α)   # variance of the Gaussian prior
@model singlebnn begin
  ws = Vector{Dual}(3)
  for i = 1:3
    @assume ws[i] ~ Normal(0, σ)
  end
  for i = 1:4
    y = singley(xs[i], ws[1], ws[2], ws[3])
    @observe ts[i] ~ Bernoulli(y)
  end
  @predict ws
end

# Sample the model
chain = sample(singlebnn, HMC(3000, 0.1, 2))

# Helper function for predicting
function singlepredict(x, chain)
  return mean([singley(x, d[:ws][1], d[:ws][2], d[:ws][3]) for d in chain[:samples]])
end

# Compute predctions
y = Float64[singlepredict(xs[i], chain) for i = 1:4]


#########################
# Demo - Priors in Dict #
#########################
using Turing, Distributions, DualNumbers, Gadfly

# Generate synthesised data
xs = rand(Normal(0.5, 1), 500)

# Define model
@model priorsinarray begin
  priors = Dict{Any, Dual}()
  @assume priors["s"] ~ InverseGamma(2, 3)
  @assume priors["m"] ~ Normal(0, sqrt(priors["s"]))
  for x in xs
    @observe x ~ Normal(priors["m"], sqrt(priors["s"]))
  end
  @predict priors
end

chain = sample(priorsinarray, HMC(1000, 0.01, 10))
m = mean([d[:priors]["m"] for d in chain[:samples]])
s = mean([d[:priors]["s"] for d in chain[:samples]])
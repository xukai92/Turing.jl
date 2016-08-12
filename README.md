# Turing.jl

This separate branch of Turing is a milestone version with HMC sampler supported and is for the evaluation purpose of the M.Phil project. The master repository of Turing is at [Turing.jl](https://github.com/yebai/Turing.jl).

### Example
```
@model gaussdemo begin
  # Define a simple Normal model with unknown mean and variance.
  @assume s ~ InverseGamma(2,3)
  @assume m ~ Normal(0,sqrt(s))
  @observe 1.5 ~ Normal(m, sqrt(s))
  @observe 2.0 ~ Normal(m, sqrt(s))
  @predict s m
end

chain = sample(gaussdemo, HMC(1000, 0.01, 15))
```

, where `1000` is the sample number, `0.01` is the leapfrog step size and `15` is the leapfrog step number.

The mean of the parameters can be computed by the following code.

```
m = mean(chain[:m])
s = mean(chain[:s])
```

## Installation

You will need Julia 0.4, which you can get from the official Julia [website](http://julialang.org/downloads/). We recommend that you install a pre-compiled package, as Turing may not work correctly with Julia built form source.

Turing is an officially registered Julia package, so the following should work:

```julia
Pkg.update()
Pkg.add("Turing")
Pkg.test("Turing")
```

If Turing can not be located, you can try the following instead:

```julia
Pkg.clone("https://github.com/yebai/Turing.jl")
Pkg.build("Turing")
Pkg.test("Turing")
```

If all tests pass, you're ready to start using Turing.

This patch adds the standard HMC sampler to Turing.

## Summary of updates

`src/samplers/hmc.jl` - the HMC sampler
- The algorithm implemented is described in **Algorithm 30.1** on P388 of MacKay's book _Information Theory, Inference and Learning Algorithms_.
-  Gradient information is computed by passing through variables in `Dual` type, which is the forward mode of automatic differentiation.

`src/samplers/support/prior.jl` - a type to pass prior information from the compiler to the HMC sampler
- This type is aimed to support `@assume` to interact with both single variables and arrays.
- There is a helper function `string()` which turns expressions like `xs[i]` into `xs[2]` with correct indexing.

`src/core/compiler.jl`
- `@assume` now passes a third parameter including the information of the prior in `Prior` type.
- `@assume` and `@observe` can pass additional parameters inside the distribution constructor, e.g. `@assume m ~ Normal(0, 1; static=true)`.
- The implementation of `@observe` passes the `logpdf()` value directly, which is not intentional according to @adscib. This is not made to be consistent with `@assume` with the interface of all samplers changed accordingly.

`src/distributions/ddistributions.jl` - a custom wrapper of common distributions to support `Dual` type variables
- The motivation to build our own wrapper is to pass `Dual` type variables to get gradient information using the forward mode of automatic differentiation.
- One principle of this wrapper is to only store parameters in `Dual` without inputing or outputting any `Dual` type, which makes it easier to amend the existing samplers using the new distribution wrapper.
- The objects from the `Distribution` package is also stored in the object of our wrapper. `rand()` and `pdf()` with `Real` type is passed to the corresponding calls in `Distribution` package.
- Multivariate distributions are supported.

`test/test_ddistribution.jl` - the test file of `dDistribution` type
- It tests each custom distribution by 1) comparing the `pdf()` result of the custom function and the `Distribution` package; 2) comparing the gradient using `ForwardDiff` package and our implementation.

`test/beta-binomial.jl` - the test file of samplers using a beta-binomial model
- Three lines of codes were added to test the HMC sampler using the existing beta-binomial test case.

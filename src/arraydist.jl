# Univariate

const VectorOfUnivariate = Distributions.Product

function arraydist(dists::AbstractVector{<:Normal{T}}) where {T}
    means = mean.(dists)
    vars = var.(dists)
    return MvNormal(means, vars)
end
function arraydist(dists::AbstractVector{<:Normal{<:TrackedReal}})
    means = vcatmapreduce(mean, dists)
    vars = vcatmapreduce(var, dists)
    return MvNormal(means, vars)
end
function arraydist(dists::AbstractVector{<:UnivariateDistribution})
    return product_distribution(dists)
end
function Distributions.logpdf(dist::VectorOfUnivariate, x::AbstractVector{<:Real})
    return sum(vcatmapreduce(logpdf, dist.v, x))
end
function Distributions.logpdf(dist::VectorOfUnivariate, x::AbstractMatrix{<:Real})
    # eachcol breaks Zygote, so we need an adjoint
    return vcatmapreduce((dist, c) -> logpdf.(dist, c), dist.v, eachcol(x))
end
@adjoint function Distributions.logpdf(dist::VectorOfUnivariate, x::AbstractMatrix{<:Real})
    # Any other more efficient implementation breaks Zygote
    f(dist, x) = [sum(logpdf.(dist.v, view(x, :, i))) for i in 1:size(x, 2)]
    return pullback(f, dist, x)
end

struct MatrixOfUnivariate{
    S <: ValueSupport,
    Tdist <: UnivariateDistribution{S},
    Tdists <: AbstractMatrix{Tdist},
} <: MatrixDistribution{S}
    dists::Tdists
end
Base.size(dist::MatrixOfUnivariate) = size(dist.dists)
function arraydist(dists::AbstractMatrix{<:UnivariateDistribution})
    return MatrixOfUnivariate(dists)
end
function Distributions.logpdf(dist::MatrixOfUnivariate, x::AbstractMatrix{<:Real})
    # Broadcasting here breaks Tracker for some reason
    # A Zygote adjoint is defined for vcatmapreduce to use broadcasting
    return sum(vcatmapreduce(logpdf, dist.dists, x))
end
function Distributions.logpdf(dist::MatrixOfUnivariate, x::AbstractArray{<:AbstractMatrix{<:Real}})
    return vcatmapreduce(x -> logpdf(dist, x), x)
end
function Distributions.logpdf(dist::MatrixOfUnivariate, x::AbstractArray{<:Matrix{<:Real}})
    return vcatmapreduce(x -> logpdf(dist, x), x)
end
function Distributions.rand(rng::Random.AbstractRNG, dist::MatrixOfUnivariate)
    return rand.(Ref(rng), dist.dists)
end

# Multivariate

struct VectorOfMultivariate{
    S <: ValueSupport,
    Tdist <: MultivariateDistribution{S},
    Tdists <: AbstractVector{Tdist},
} <: MatrixDistribution{S}
    dists::Tdists
end
Base.size(dist::VectorOfMultivariate) = (length(dist.dists[1]), length(dist))
Base.length(dist::VectorOfMultivariate) = length(dist.dists)
function arraydist(dists::AbstractVector{<:MultivariateDistribution})
    return VectorOfMultivariate(dists)
end
function Distributions.logpdf(dist::VectorOfMultivariate, x::AbstractMatrix{<:Real})
    # eachcol breaks Zygote, so we define an adjoint
    return sum(vcatmapreduce(logpdf, dist.dists, eachcol(x)))
end
function Distributions.logpdf(dist::VectorOfMultivariate, x::AbstractArray{<:AbstractMatrix{<:Real}})
    return reshape(vcatmapreduce(x -> logpdf(dist, x), x), size(x))
end
function Distributions.logpdf(dist::VectorOfMultivariate, x::AbstractArray{<:Matrix{<:Real}})
    return reshape(vcatmapreduce(x -> logpdf(dist, x), x), size(x))
end
@adjoint function Distributions.logpdf(dist::VectorOfMultivariate, x::AbstractMatrix{<:Real})
    f(dist, x) = sum(vcatmapreduce(i -> logpdf(dist.dists[i], view(x, :, i)), 1:size(x, 2)))
    return pullback(f, dist, x)
end
function Distributions.rand(rng::Random.AbstractRNG, dist::VectorOfMultivariate)
    init = reshape(rand(rng, dist.dists[1]), :, 1)
    return mapreduce(i -> rand(rng, dist.dists[i]), hcat, 2:length(dist); init = init)
end
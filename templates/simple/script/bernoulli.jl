import Random

Random.seed!(0)

n_samples = 1000
samples = Base.randn(1000)
σ² = sum(samples .^ 2) / length(samples)
print("$σ²")

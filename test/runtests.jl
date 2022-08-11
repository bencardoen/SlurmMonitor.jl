using SlurmMonitor
using Test

@testset "SlurmMonitor.jl" begin
    @testset "ping" begin
        h = "localhost"
        res = pinghost(h)
        @test iszero(res[end])
        @test all(res[1:end-1] .>= 0)
        h = "notahost"
        res = pinghost(h)
        @test res[end] == 100
        @test all(isinf.(res[1:end-1]))
    end
end

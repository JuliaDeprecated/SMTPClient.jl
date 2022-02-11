using Test
import Base64: base64decode
using Markdown
using SMTPClient

@testset "SMTPClient" begin
  for t ∈ (:send, :error)
    @info "testset: $t..."
    include("./$t.jl")
  end
end

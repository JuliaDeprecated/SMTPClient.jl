using Base.Test

using SMTPClient


@testset "Error message for Humans(TM)" begin
    let errmsg = "Couldn't resolve host name"
        server = "smtp://nonexists"
        body = IOBuffer("test")

        try
            send(server, ["nobody@earth"], "nobody@earth", body)
            @assert false, "send should fail"
        catch e
            @test contains(string(e), errmsg)
        end
    end
end


@testset "Non-blocking send" begin
    let errmsg = "Couldn't resolve host name"
        opt = SendOptions(blocking = false)
        server = "smtp://nonexists"
        body = IOBuffer("test")

        future = send(server, ["nobody@earth"], "nobody@earth", body, opt)
        @test future isa Future

        e = fetch(future)
        @test contains(string(e), errmsg)
    end
end

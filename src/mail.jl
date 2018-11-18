send(url::AbstractString, to::AbstractVector{<:AbstractString},
              from::AbstractString, body::IO, opts::SendOptions = SendOptions()) =
  do_send(String(url), map(String, collect(to)), String(from), opts, ReadData(body))

function do_send(url::String, to::Vector{String}, from::String, options::SendOptions,
                 rd::ReadData)
  ctxt = nothing
  try
    ctxt = ConnContext(url = url, rd = rd, options = options)

    setmail_from!(ctxt, from)
    setmail_rcpt!(ctxt, to)

    connect(ctxt)
    getresponse!(ctxt)

    ctxt.resp
  finally
    cleanup!(ctxt)
  end
end


function exec_as_multi(ctxt)
  curl = ctxt.curl
  curlm = curl_multi_init()

  if curlm == C_NULL
    error("Unable to initialize curl_multi_init()")
  end

  try
    if isa(ctxt.options.callback, Function)
      ctxt.options.callback(curl)
    end

    @ce_curlm curl_multi_add_handle curl

    n_active = Array{Int}(1)
    n_active[1] = 1

    no_to = 30 * 24 * 3600.0
    request_timeout = 0.001 + (ctxt.options.request_timeout == 0.0 ? no_to : ctxt.options.request_timeout)

    started_at = time()
    time_left = request_timeout

    # poll_fd is unreliable when multiple parallel fds are active, hence using curl_multi_perform
    cmc = curl_multi_perform(curlm, n_active);
    while (n_active[1] > 0) &&  (time_left > 0)
      nb1 = ctxt.bytes_recd
      cmc = curl_multi_perform(curlm, n_active);
      if(cmc != CURLM_OK) error("curl_multi_perform() failed: " * string(curl_multi_strerror(cmc))) end

      nb2 = ctxt.bytes_recd

      if (nb2 > nb1)
        yield() # Just yield to other tasks
      else
        sleep(0.005) # Just to prevent unnecessary CPU spinning
      end

      time_left = request_timeout - (time() - started_at)
    end
    # END OF curl_multi_perform

    if (n_active[1] == 0)
      msgs_in_queue = Array{Cint}(1)
      p_msg::Ptr{CURLMsg2} = curl_multi_info_read(curlm, msgs_in_queue)

      while (p_msg != C_NULL)
        # println("Messages left in Q : " * string(msgs_in_queue[1]))
        msg = unsafe_load(p_msg)

        if (msg.msg == CURLMSG_DONE)
          ec = convert(Int, msg.data)
          if (ec != CURLE_OK)
            # println("Result of transfer: " * string(msg.data))
            throw("Error executing request : " * string(curl_easy_strerror(ec)))
          else
            getresponse!(ctxt)
          end
        end

        p_msg = curl_multi_info_read(curlm, msgs_in_queue)
      end
    else
      error("request timed out")
    end

  finally
    curl_multi_remove_handle(curlm, curl)
    curl_multi_cleanup(curlm)
  end

  ctxt.resp
end

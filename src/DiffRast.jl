module DiffRast

using GL
using GL.LibGLFW
using GL.CImGui
using GL.ModernGL

function create_context()
    GL.init(4, 3)
    GL.Context("DiffRast"; width=512, height=512, visible=false)
end

function destroy_context(ctx::GL.Context)
    GL.delete!(ctx)
end

function data_to_image(data::AbstractArray{Float32})
    channels, width, height = size(data)
    type = channels == 4 ? RGBA{Float64} : RGB{Float64}
    image = Array{type, 2}(undef, height, width)
    for h in 1:height
        for w in 1:width
            w_index = (w - 1) * channels
            h_index = (height - h) * width * channels

            if channels == 4
                pixel = RGBA(
                    data[h_index + w_index + 1],
                    data[h_index + w_index + 2],
                    data[h_index + w_index + 3],
                    data[h_index + w_index + 4] == 0.0 ? 0.0 : 1.0
                )
            elseif channels == 3
                pixel = RGB(
                    data[h_index + w_index + 1],
                    data[h_index + w_index + 2],
                    data[h_index + w_index + 3]
                )
            else
                error("Invalid number of channels")
            end
            image[h, w] = pixel
        end
    end

    image
end

include("rasterize.jl")

end

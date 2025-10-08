module images

using FileIO
save("img.png", rand(100, 100))
img = load("img.png")

end # module images

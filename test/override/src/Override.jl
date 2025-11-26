module Override

import Artefact

mystery() = print("override")

const mystery_value = ENV["OVERRIDE_MYSTERY"]
mystery2() = print(mystery_value)

end # module Override

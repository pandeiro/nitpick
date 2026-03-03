import types
import options
import jsony

echo "Testing types with jsony..."
var p: Profile
p.pinned = some(Tweet())
echo p.pinned.isSome
echo p.toJson()

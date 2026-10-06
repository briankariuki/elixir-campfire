import MessageList from "./message_list"
import MessagePager from "./message_pager"
import Composer from "./composer"
import LocalTime from "./local_time"
import Visibility from "./visibility"
import Copy from "./copy"
import Lightbox from "./lightbox"
import Filter from "./filter"
// Side-effect module: delegated listeners for the translation popups (works without a LiveView)
import "./popup"
import Share from "./share"

export default {MessageList, MessagePager, Composer, LocalTime, Visibility, Copy, Lightbox, Filter, Share}

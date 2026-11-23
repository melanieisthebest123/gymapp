import Foundation
import Supabase

enum SupabaseConfig {
    // The publishable key is designed to ship inside apps. Data is protected by row level
    // security (see supabase/schema.sql). Never put the secret/service_role key here.
    static let url = URL(string: "https://vfbafnnrehsdmotjyzwm.supabase.co")!
    static let publishableKey = "sb_publishable_jR5LBn89uINrwdvgUo9H0w_XzL006Vb"

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true)))
}

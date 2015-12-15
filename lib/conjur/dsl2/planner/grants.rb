require 'conjur/dsl2/planner/base'

module Conjur
  module DSL2
    module Planner
      class Grant < Base
        # Plans a role grant.
        # 
        # The Grant record can list multiple roles and members. Each member should
        # be granted every role. If the +replace+ option is set, then any existing
        # grant on a role that is *not* given should be revoked.
        def do_plan
          roles = Array(record.roles)
          members = Array(record.members)
          given_grants = Hash.new { |hash, key| hash[key] = [] }
          requested_grants = Hash.new { |hash, key| hash[key] = [] }
          roles.each do |role|
            grants = begin
              api.role(scoped_roleid(role)).members
            rescue RestClient::ResourceNotFound
              []
            end
            
            grants.each do |grant|
              # Don't revoke admins from roles
              next if grant.admin_option
              given_grants[scoped_roleid(role)].push [ grant.member.roleid, grant.admin_option ]
            end
            members.each do |member|
              requested_grants[scoped_roleid(role)].push [ scoped_roleid(member.role), !!member.admin ]
            end
          end
          
          roles.each do |role|
            roleid = scoped_roleid(role)
            given = given_grants[roleid]
            requested = requested_grants[roleid]
            
            (Set.new(requested) - Set.new(given)).each do |p|
              member, admin = p
              grant = Conjur::DSL2::Types::Grant.new
              grant.role = role_record roleid
              grant.member = Conjur::DSL2::Types::Member.new role_record(member)
              grant.member.admin = true if admin
              action grant
            end
            if record.replace
              (Set.new(given) - Set.new(requested)).each do |p|
                member, admin = p
                revoke = Conjur::DSL2::Types::Revoke.new
                revoke.role = role_record roleid
                revoke.member = role_record(member)
                action revoke
              end
            end
          end
        end
      end
    end
  end
end

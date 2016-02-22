module Conjur
  module DSL2
    class Resolver
      attr_reader :account, :ownerid, :namespace
      
      class << self
        # Resolve records to the specified owner id and namespace.
        def resolve account, ownerid, namespace, records
          resolver_classes = [ IdResolver, AccountResolver, OwnerResolver, FlattenResolver ]
          resolver_classes.each do |cls|
            resolver = cls.new account, ownerid, namespace
            records = resolver.resolve records
          end
          records
        end
      end
      
      # +account+ is required. It's the default account whenever no account is specified.
      # +ownerid+ is required. Any records without an owner will be assigned this owner. The exception
      # is records defined in a policy, which are always owned by the policy role unless an explicit owner
      # is indicated (which would be rare).
      # +namespace+ is optional. It's prepended to the id of every record, except for ids which begin
      # with a '/' character.
      def initialize account, ownerid, namespace = nil
        @account = account
        @ownerid   = ownerid
        @namespace = namespace
        
        raise "account is required" unless account
        raise "ownerid is required" unless ownerid
        raise "ownerid must be fully qualified" unless ownerid.split(":", 3).length == 3
      end
      
      protected
      
      # Traverse an Array-ish of records, calling a +handler+ method for each one.
      # If a record is a Policy, then the +policy_handler+ is invoked, after the +handler+.
      def traverse records, visited, handler, policy_handler = nil
        Array(records).flatten.each do |record|
          next unless visited.add?(id_of(record))

          handler.call record, visited
          policy_handler.call record, visited if policy_handler && record.is_a?(Types::Policy)
        end
      end
      
      def id_of record
        record.object_id
      end
    end
    
    # Makes all ids absolute, by prepending the namespace (if any) and the enclosing policy (if any).
    class IdResolver < Resolver
      def resolve records
        traverse records, Set.new, method(:resolve_id), method(:on_resolve_policy)
      end
      
      def resolve_id record, visited
        if record.respond_to?(:id)
          id = record.id
          if id.blank?
            raise "#{record.to_s} has no id, and no namespace is available to populate it" unless namespace
            record.id = namespace
          elsif id[0] == '/'
            record.id = id[1..-1]
          else
            record.id = [ namespace, id ].compact.join('/')
          end
        end
        
        traverse record.referenced_records, visited, method(:resolve_id), method(:on_resolve_policy)
      end
      
      def on_resolve_policy policy, visited
        saved_namespace = @namespace
        @namespace = policy.id
        traverse policy.body, visited, method(:resolve_id), method(:on_resolve_policy)
      ensure
        @namespace = saved_namespace
      end
    end
    
    # Updates all nil +account+ fields to the default account.
    class AccountResolver < Resolver
      def resolve records
        traverse records, Set.new, method(:resolve_account), method(:on_resolve_policy)
      end
      
      def resolve_account record, visited
        if record.respond_to?(:account) && record.account.nil?
          record.account = @account
        end
        traverse record.referenced_records, visited, method(:resolve_account), method(:on_resolve_policy)
      end
      
      def on_resolve_policy policy, visited
        traverse policy.body, visited, method(:resolve_account), method(:on_resolve_policy)
      end
    end
    
    # Sets the owner field for any records which support it, and don't have an owner specified.
    # Within a policy, the default owner is the policy role. For global records, the 
    # default owner is the +ownerid+ specified in the constructor.
    class OwnerResolver < Resolver
      def resolve records
        traverse records, Set.new, method(:resolve_owner), method(:on_resolve_policy)
      end
      
      def resolve_owner record, visited
        if record.respond_to?(:owner) && record.owner.nil?
          record.owner = Types::Role.new(@ownerid)
        end
      end
      
      def on_resolve_policy policy, visited
        saved_ownerid = @ownerid
        @ownerid = [ policy.account || @account, "policy", policy.id ].join(":")
        traverse policy.body, visited, method(:resolve_owner), method(:on_resolve_policy)
      ensure
        @ownerid = saved_ownerid
      end
    end
    
    # Flattens and sorts all records into a single list, including YAML lists and policy body.
    class FlattenResolver < Resolver
      def resolve records
        @result = []
        traverse records, Set.new, method(:resolve_record), method(:on_resolve_policy)
        @result.flatten.sort do |a,b|
          base_score = sort_score(a) - sort_score(b)
          if base_score == 0
            if b.referenced_records.member?(a)
              -1
            elsif a.referenced_records.member?(b)
              1
            else
              0
            end
          else
            base_score
          end
        end
      end
      
      protected
      
      # Select things uniquely by class and id, in this resolver.
      def id_of record
        if record.respond_to?(:id)
          [ record.id, record.class.name ].join("@")
        else
          super
        end
      end
      
      # Sort "Create" and "Record" objects to the front.
      def sort_score record
        if record.is_a?(Types::Create) || record.is_a?(Types::Record)
          -1
        else
          0
        end
      end
      
      # Add the record to the result.
      def resolve_record record, visited
        @result += Array(record)
      end

      # Recurse on the policy body records.
      def on_resolve_policy policy, visited
        body = policy.body
        policy.remove_instance_variable "@body"
        traverse body, visited, method(:resolve_record), method(:on_resolve_policy)
      end
    end
  end
end

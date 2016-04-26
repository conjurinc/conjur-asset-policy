Feature: "elevate" can be used to ensure success of write operations

  Background:
    Given I load the policy:
    """
    ---
    - !group ops
    - !group dev
    - !permit
      role: !group ops
      privilege: elevate
      resource: !resource
        account: '!'
        kind: '!'
        id: /conjur
    - !user alice
    - !grant
      role: !group ops
      member: !user alice
    - !host
      id: host-01.app
      owner: !group dev
    """
    And I login as "alice"  

  Scenario: Manipulation of a foreign record fails without elevate
    Then I load the policy:
    """
    - !user bob
    - !permit
      role: !user bob
      privilege: [ execute, update ]
      resource: !host host-01.app
    """

  Scenario: With elevate, a foreign record can be manipulated
    Then I load the policy with "elevate" privilege:
    """
    - !user bob
    - !permit
      role: !user bob
      privilege: [ execute, update ]
      resource: !host host-01.app
    """

interface votingContract {
    function getTokenProposalDetails() external view returns(address, uint, uint, uint);
    function getExpiry() external view returns (uint);
    function getContractType () external view returns (uint);
}

contract abstractCaelum {
    function isMasternodeOwner(address _candidate) public view returns(bool);
    function addToWhitelist(address _ad, uint _amount, uint daysAllowed) internal;
    function addMasternode(address _candidate) internal returns(uint);
    function deleteMasternode(uint entityAddress) internal returns(bool success);
    function getLastPerUser(address _candidate) public view returns (uint);
    function getMiningReward() public view returns(uint);
}

contract NewMemberProposal is votingContract {

    enum VOTE_TYPE {TOKEN, TEAM}
    VOTE_TYPE public contractType = VOTE_TYPE.TEAM;

    address memberAddress;
    uint totalMasternodes;
    uint votingDurationInDays;

    /**
     * @dev Create a new vote proposal for a team member.
     * @param _contract Future team member's address
     * @param _total How many masternodes do we want to give
     * @param _voteDuration How many days is this vote available
     */
    constructor(address _contract, uint _total, uint _voteDuration) public {
        require(_voteDuration >= 14 && _voteDuration <= 50, "Proposed voting duration does not meet requirements");
        memberAddress = _contract;
        totalMasternodes = _total;
        votingDurationInDays = _voteDuration;
    }

    /**
     * @dev Retuns all details about this proposal
     */
    function getTokenProposalDetails() public view returns(address, uint, uint, uint) {
        return (memberAddress, totalMasternodes, 0, uint(contractType));
    }

    /**
     * @dev Displays the expiry date of contract
     * @return uint Days valid
     */
    function getExpiry() external view returns (uint) {
        return votingDurationInDays;
    }

    /**
     * @dev Displays the type of contract
     * @return uint Enum value {TOKEN, TEAM}
     */
    function getContractType () external view returns (uint){
        return uint(contractType);
    }
}

contract NewTokenProposal is votingContract {

    enum VOTE_TYPE {TOKEN, TEAM}

    VOTE_TYPE public contractType = VOTE_TYPE.TOKEN;
    address contractAddress;
    uint requiredAmount;
    uint validUntil;
    uint votingDurationInDays;


    /**
     * @dev Create a new vote proposal for an ERC20 token.
     * @param _contract ERC20 contract
     * @param _amount How many tokens are required as collateral
     * @param _valid How long do we accept these tokens on the contract (UNIX timestamp)
     * @param _voteDuration How many days is this vote available
     */
    constructor(address _contract, uint _amount, uint _valid, uint _voteDuration) public {
        require(_voteDuration >= 14 && _voteDuration <= 50, "Proposed voting duration does not meet requirements");

        contractAddress = _contract;
        requiredAmount = _amount;
        validUntil = _valid;
        votingDurationInDays = _voteDuration;
    }

    /**
     * @dev Retuns all details about this proposal
     */
    function getTokenProposalDetails() public view returns(address, uint, uint, uint) {
        return (contractAddress, requiredAmount, validUntil, uint(contractType));
    }

    /**
     * @dev Displays the expiry date of contract
     * @return uint Days valid
     */
    function getExpiry() external view returns (uint) {
        return votingDurationInDays;
    }

    /**
     * @dev Displays the type of contract
     * @return uint Enum value {TOKEN, TEAM}
     */
    function getContractType () external view returns (uint){
        return uint(contractType);
    }
}

contract CaelumVotings {
    using SafeMath for uint;

    enum VOTE_TYPE {TOKEN, TEAM}

    struct Proposals {
        address tokenContract;
        uint totalVotes;
        uint proposedOn;
        uint acceptedOn;
        VOTE_TYPE proposalType;
    }

    struct Voters {
        bool isVoter;
        address owner;
        uint[] votedFor;
    }

    uint MAJORITY_PERCENTAGE_NEEDED = 60;
    uint MINIMUM_VOTERS_NEEDED = 10;
    bool public proposalPending;

    mapping(uint => Proposals) public proposalList;
    mapping (address => Voters) public voterMap;
    mapping(uint => address) public voterProposals;
    uint public proposalCounter;
    uint public votersCount;

    /**
     * @notice Define abstract functions for later user
     */
    function isMasternodeOwner(address _candidate) public view returns(bool);
    function addToWhitelist(address _ad, uint _amount, uint daysAllowed) internal;
    function addMasternode(address _candidate) internal returns(uint);
    function updateMasternodeAsTeamMember(address _member) internal returns (bool);
    function isTeamMember (address _candidate) public view returns (bool);

    /**
     * @dev Create a new proposal.
     * @param _contract Proposal contract address
     * @return uint ProposalID
     */
    function pushProposal(address _contract) public returns (uint) {
        if(proposalCounter != 0)
        require (pastProposalTimeRules (), "You need to wait 90 days before submitting a new proposal.");
        require (!proposalPending, "Another proposal is pending.");

        uint _contractType = votingContract(_contract).getContractType();
        proposalList[proposalCounter] = Proposals(_contract, 0, now, 0, VOTE_TYPE(_contractType));

        proposalCounter++;
        proposalPending = true;

        return proposalCounter - 1;
    }

    /**
     * @dev Internal function that handles the proposal after it got accepted.
     * This function determines if the proposal is a token or team member proposal and executes the corresponding functions.
     * @return uint Returns the proposal ID.
     */
    function handleLastProposal () internal returns (uint) {
        uint _ID = proposalCounter.sub(1);

        proposalList[_ID].acceptedOn = now;
        proposalPending = false;

        address _address;
        uint _required;
        uint _valid;
        uint _type;
        (_address, _required, _valid, _type) = getTokenProposalDetails(_ID);

        if(_type == uint(VOTE_TYPE.TOKEN)) {
            addToWhitelist(_address,_required,_valid);
        }

        if(_type == uint(VOTE_TYPE.TEAM)) {
            if(_required != 0) {
                for (uint i = 0; i < _required; i++) {
                    addMasternode(_address);
                }
            } else {
                addMasternode(_address);
            }
            updateMasternodeAsTeamMember(_address);
        }

        return _ID;
    }

    /**
     * @dev Rejects the last proposal after the allowed voting time has expired and it's not accepted.
     */
    function discardRejectedProposal() public returns (bool) {
        if (LastProposalCanDiscard())
        proposalPending = false;
        return (true);
    }

    /**
     * @dev Checks if the last proposal allowed voting time has expired and it's not accepted.
     * @return bool
     */
    function LastProposalCanDiscard () public view returns (bool) {
        uint daysBeforeDiscard = votingContract(proposalList[proposalCounter - 1].tokenContract).getExpiry();
        uint entryDate = proposalList[proposalCounter - 1].proposedOn;
        uint expiryDate = entryDate + (daysBeforeDiscard * 1 days);

        if (now >= expiryDate)
        return true;
    }

    /**
     * @dev Returns all details about a proposal
     */
    function getTokenProposalDetails(uint proposalID) public view returns(address, uint, uint, uint) {
        return votingContract(proposalList[proposalID].tokenContract).getTokenProposalDetails();
    }

    /**
     * @dev Returns if our 90 day cooldown has passed
     * @return bool
     */
    function pastProposalTimeRules() public view returns (bool) {
        uint lastProposal = proposalList[proposalCounter - 1].proposedOn;
        if (now >= lastProposal + 90 days)
        return true;
    }


    /**
     * @dev Allow any masternode user to become a voter.
     */
    function becomeVoter() public  {
        require (isMasternodeOwner(msg.sender), "User has no masternodes");
        require (!voterMap[msg.sender].isVoter, "User Already voted for this proposal");

        voterMap[msg.sender].owner = msg.sender;
        voterMap[msg.sender].isVoter = true;
        votersCount = votersCount + 1;
    }

    /**
     * @dev Allow voters to submit their vote on a proposal. Voters can only cast 1 vote per proposal.
     * If the proposed vote is about adding Team members, only Team members are able to vote.
     * A proposal can only be published if the total of votes is greater then MINIMUM_VOTERS_NEEDED.
     * @param proposalID proposalID
     */
    function voteProposal(uint proposalID) public returns (bool success) {
        require(voterMap[msg.sender].isVoter, "Sender not listed as voter");
        require(proposalID >= 0, "No proposal was selected.");
        require(proposalID <= proposalCounter, "Proposal out of limits.");
        require(voterProposals[proposalID] != msg.sender, "Already voted.");
        require(votersCount >= MINIMUM_VOTERS_NEEDED, "Not enough voters in existence to push a proposal");

        if(proposalList[proposalID].proposalType == VOTE_TYPE.TEAM) {
            require (isTeamMember(msg.sender), "Restricted for team members");
        }

        voterProposals[proposalID] = msg.sender;
        proposalList[proposalID].totalVotes++;

        if(reachedMajority(proposalID)) {
            // This is the prefered way of handling vote results. It costs more gas but prevents tampering.
            // If gas is an issue, you can comment handleLastProposal out and call it manually as onlyOwner.
            handleLastProposal();
            return true;
        }
    }

    /**
     * @dev Check if a proposal has reached the majority vote
     * @param proposalID Token ID
     * @return bool
     */
    function reachedMajority (uint proposalID) public view returns (bool) {
        uint getProposalVotes = proposalList[proposalID].totalVotes;
        if (getProposalVotes >= majority())
        return true;
    }

    /**
     * @dev Internal function that calculates the majority
     * @return uint Total of votes needed for majority
     */
    function majority () internal view returns (uint) {
        uint a = (votersCount * MAJORITY_PERCENTAGE_NEEDED );
        return a / 100;
    }

}

contract CaelumAcceptERC20 is abstractCaelum {
    using SafeMath for uint;

    address[] public tokensList;
    bool setOwnContract = true;

    struct _whitelistTokens {
        address tokenAddress;
        bool active;
        uint requiredAmount;
        uint validUntil;
        uint timestamp;
    }

    mapping(address => mapping(address => uint)) public tokens;
    mapping(address => _whitelistTokens) acceptedTokens;

    event Deposit(address token, address user, uint amount, uint balance);
    event Withdraw(address token, address user, uint amount, uint balance);

    function getMiningReward() public view returns(uint);


    /**
     * @notice Allow the dev to set it's own token as accepted payment.
     * @dev Can be hardcoded in the constructor. Given the contract size, we decided to separate it.
     * @return bool
     */
    function addOwnToken() public returns (bool) {
        require(setOwnContract);
        addToWhitelist(this, 5000 * 1e8, 36500);
        setOwnContract = false;
        return true;
    }

    // TODO: Set visibility
    /**
     * @notice Add a new token as accepted payment method.
     * @param _token Token contract address.
     * @param _amount Required amount of this Token as collateral
     * @param daysAllowed How many days will we accept this token?
     */
    function addToWhitelist(address _token, uint _amount, uint daysAllowed) internal {
        _whitelistTokens storage newToken = acceptedTokens[_token];
        newToken.tokenAddress = _token;
        newToken.requiredAmount = _amount;
        newToken.timestamp = now;
        newToken.validUntil = now + (daysAllowed * 1 days);
        newToken.active = true;

        tokensList.push(_token);
    }

    /**
     * @dev internal function to determine if we accept this token.
     * @param _ad Token contract address
     * @return bool
     */
    function isAcceptedToken(address _ad) internal view returns(bool) {
        return acceptedTokens[_ad].active;
    }

    /**
     * @dev internal function to determine the requiredAmount for a specific token.
     * @param _ad Token contract address
     * @return bool
     */
    function getAcceptedTokenAmount(address _ad) internal view returns(uint) {
        return acceptedTokens[_ad].requiredAmount;
    }

    /**
     * @dev internal function to determine if the token is still accepted timewise.
     * @param _ad Token contract address
     * @return bool
     */
    function isValid(address _ad) internal view returns(bool) {
        uint endTime = acceptedTokens[_ad].validUntil;
        if (block.timestamp < endTime) return true;
        return false;
    }

    /**
     * @notice Returns an array of all accepted token. You can get more details by calling getTokenDetails function with this address.
     * @return array Address
     */
    function listAcceptedTokens() public view returns(address[]) {
        return tokensList;
    }

    /**
     * @notice Returns a full list of the token details
     * @param token Token contract address
     */
    function getTokenDetails(address token) public view returns(address ad,uint required, bool active, uint valid) {
        return (acceptedTokens[token].tokenAddress, acceptedTokens[token].requiredAmount,acceptedTokens[token].active, acceptedTokens[token].validUntil);
    }

    /**
     * @notice Public function that allows any user to deposit accepted tokens as collateral to become a masternode.
     * @param token Token contract address
     * @param amount Amount to deposit
     */
    function depositCollateral(address token, uint amount) public {
        require(isAcceptedToken(token), "ERC20 not authorised");  // Should be a token from our list
        require(amount == getAcceptedTokenAmount(token));         // The amount needs to match our set amount
        require(isValid(token));                                  // It should be called within the setup timeframe

        tokens[token][msg.sender] = tokens[token][msg.sender].add(amount);

        require(StandardToken(token).transferFrom(msg.sender, this, amount), "error with token");
        emit Deposit(token, msg.sender, amount, tokens[token][msg.sender]);

        addMasternode(msg.sender);
    }

    /**
     * @notice Public function that allows any user to withdraw deposited tokens and stop as masternode
     * @param token Token contract address
     * @param amount Amount to withdraw
     */
    function withdrawCollateral(address token, uint amount) public {
        require(token != 0); // token should be an actual address
        require(isAcceptedToken(token), "ERC20 not authorised"); // Should be a token from our list
        require(isMasternodeOwner(msg.sender)); // The sender must be a masternode prior to withdraw
        require(tokens[token][msg.sender] == amount); // The amount must be exactly whatever is deposited

        uint amountToWithdraw = tokens[token][msg.sender];
        tokens[token][msg.sender] = 0;

        deleteMasternode(getLastPerUser(msg.sender));

        if (!StandardToken(token).transfer(msg.sender, amountToWithdraw)) revert();
        emit Withdraw(token, msg.sender, amountToWithdraw, amountToWithdraw);
    }

}

contract CaelumMasternode is Ownable, CaelumVotings, CaelumAcceptERC20{
    using SafeMath for uint;

    bool onTestnet = false;
    bool genesisAdded = false;

    uint  masternodeRound;
    uint  masternodeCandidate;
    uint  masternodeCounter;
    uint  masternodeEpoch;
    uint  miningEpoch;

    uint rewardsProofOfWork;
    uint rewardsMasternode;
    uint rewardsGlobal = 50 * 1e8;

    uint MINING_PHASE_DURATION_BLOCKS = 4500;

    struct MasterNode {
        address accountOwner;
        bool isActive;
        bool isTeamMember;
        uint storedIndex;
        uint startingRound;
        uint[] indexcounter;
    }

    uint[] userArray;
    address[] userAddressArray;

    mapping(uint => MasterNode) userIndexStruct; // UINT masterMapping
    mapping(address => MasterNode) userAddresCount; //masterMapping
    mapping(address => uint) userAddressIndex;

    event Deposit(address token, address user, uint amount, uint balance);
    event Withdraw(address token, address user, uint amount, uint balance);

    event NewMasternode(address candidateAddress, uint timeStamp);
    event RemovedMasternode(address candidateAddress, uint timeStamp);

    /**
     * @dev Add the genesis accounts
     */
    function addGenesis() public {
        require(!genesisAdded);
        addMasternode(msg.sender);
        updateMasternodeAsTeamMember(msg.sender);
        genesisAdded = true; // Forever lock this.
    }

    /**
     * @dev Add a user as masternode. Called as internal since we only add masternodes by depositing collateral or by voting.
     * @param _candidate Candidate address
     * @return uint Masternode index
     */
    function addMasternode(address _candidate) internal returns(uint) {
        userIndexStruct[masternodeCounter].accountOwner = _candidate;
        userIndexStruct[masternodeCounter].isActive = true;
        userIndexStruct[masternodeCounter].startingRound = masternodeRound + 1;
        userIndexStruct[masternodeCounter].storedIndex = masternodeCounter;

        userAddresCount[_candidate].accountOwner = _candidate;
        userAddresCount[_candidate].indexcounter.push(masternodeCounter);

        userArray.push(userArray.length);
        masternodeCounter++;
        return masternodeCounter - 1; //
    }

    /**
     * @dev Allow us to update a masternode's round to keep progress
     * @param _candidate ID of masternode
     */
    function updateMasternode(uint _candidate) internal returns(bool) {
        userIndexStruct[_candidate].startingRound++;
        return true;
    }

    /**
     * @dev Allow us to update a masternode to team member status
     * @param _member address
     */
    function updateMasternodeAsTeamMember(address _member) internal returns (bool) {
        userAddresCount[_member].isTeamMember = true;
        return (true);
    }

    /**
     * @dev Let us know if an address is part of the team.
     * @param _member address
     */
    function isTeamMember (address _member) public view returns (bool) {
        if (userAddresCount[_member].isTeamMember)
        return true;
    }

    /**
     * @dev Remove a specific masternode
     * @param _masternodeID ID of the masternode to remove
     */
    function deleteMasternode(uint _masternodeID) internal returns(bool success) {

        uint rowToDelete = userIndexStruct[_masternodeID].storedIndex;
        uint keyToMove = userArray[userArray.length - 1];

        userIndexStruct[_masternodeID].isActive = userIndexStruct[_masternodeID].isActive = (false);
        userArray[rowToDelete] = keyToMove;
        userIndexStruct[keyToMove].storedIndex = rowToDelete;
        userArray.length = userArray.length - 1;

        removeFromUserCounter(_masternodeID);

        // TODO Why did i comment this out???
        //delete userIndexStruct[entityAddress];
        //delete userAddresCount[isPartOf(entityAddress)];

        return true;
    }

    /**
     * @dev returns what account belongs to a masternode
     */
    function isPartOf(uint mnid) public view returns (address) {
        return userIndexStruct[mnid].accountOwner;
    }

    /**
     * @dev Internal function to remove a masternode from a user address if this address holds multple masternodes
     * @param index MasternodeID
     */
    function removeFromUserCounter(uint index)  internal returns(uint[]) {
        address belong = isPartOf(index);

        if (index >= userAddresCount[belong].indexcounter.length) return;

        for (uint i = index; i<userAddresCount[belong].indexcounter.length-1; i++){
            userAddresCount[belong].indexcounter[i] = userAddresCount[belong].indexcounter[i+1];
        }

        delete userAddresCount[belong].indexcounter[userAddresCount[belong].indexcounter.length-1];
        userAddresCount[belong].indexcounter.length--;
        return userAddresCount[belong].indexcounter;
    }

    /**
     * @dev Primary contract function to update the current user and prepare the next one.
     * A number of steps have been token to ensure the contract can never run out of gas when looping over our masternodes.
     */
    function setMasternodeCandidate() internal returns(address) {

        uint hardlimitCounter = 0;

        while (getFollowingCandidate() == 0x0) {
            // We must return a value not to break the contract. Require is a secondary killswitch now.
            require(hardlimitCounter < 6, "Failsafe switched on");
            // Choose if loop over revert/require to terminate the loop and return a 0 address.
            if (hardlimitCounter == 5) return (0);
            masternodeRound = masternodeRound + 1;
            masternodeCandidate = 0;
            hardlimitCounter++;
        }

        if (masternodeCandidate == masternodeCounter - 1) {
            masternodeRound = masternodeRound + 1;
            masternodeCandidate = 0;
        }

        for (uint i = masternodeCandidate; i < masternodeCounter; i++) {
            if (userIndexStruct[i].isActive) {
                if (userIndexStruct[i].startingRound == masternodeRound) {
                    updateMasternode(i);
                    masternodeCandidate = i;
                    return (userIndexStruct[i].accountOwner);
                }
            }
        }

        masternodeRound = masternodeRound + 1;
        return (0);

    }

    /**
     * @dev Helper function to loop trough our masternodes at start and return the correct round
     */
    function getFollowingCandidate() internal view returns(address _address) {
        uint tmpRound = masternodeRound;
        uint tmpCandidate = masternodeCandidate;

        if (tmpCandidate == masternodeCounter - 1) {
            tmpRound = tmpRound + 1;
            tmpCandidate = 0;
        }

        for (uint i = masternodeCandidate; i < masternodeCounter; i++) {
            if (userIndexStruct[i].isActive) {
                if (userIndexStruct[i].startingRound == tmpRound) {
                    tmpCandidate = i;
                    return (userIndexStruct[i].accountOwner);
                }
            }
        }

        tmpRound = tmpRound + 1;
        return (0);
    }

    /**
     * @dev Displays all masternodes belonging to a user address.
     */
    function belongsToUser(address userAddress) public view returns(uint[]) {
        return (userAddresCount[userAddress].indexcounter);
    }

    /**
     * @dev Helper function to know if an address owns masternodes
     */
    function isMasternodeOwner(address _candidate) public view returns(bool) {
        if(userAddresCount[_candidate].indexcounter.length <= 0) return false;
        if (userAddresCount[_candidate].accountOwner == _candidate)
        return true;
    }

    /**
     * @dev Helper function to get the last masternode belonging to a user
     */
    function getLastPerUser(address _candidate) public view returns (uint) {
        return userAddresCount[_candidate].indexcounter[userAddresCount[_candidate].indexcounter.length - 1];
    }


    /**
     * @dev Calculate and set the reward schema for Caelum.
     * Each mining phase is decided by multiplying the MINING_PHASE_DURATION_BLOCKS with factor 10.
     * Depending on the outcome (solidity always rounds), we can detect the current stage of mining.
     * First stage we cut the rewards to 5% to prevent instamining.
     * Last stage we leave 2% for miners to incentivize keeping miners running.
     */
    function calculateRewardStructures() internal {
        //ToDo: Set
        uint _global_reward_amount = getMiningReward(); //reward();
        uint getStageOfMining = miningEpoch / MINING_PHASE_DURATION_BLOCKS * 10;

        if (getStageOfMining < 10) {
            rewardsProofOfWork = _global_reward_amount / 100 * 5;
            rewardsMasternode = 0;
            return;
        }

        if (getStageOfMining > 90) {
            rewardsProofOfWork = _global_reward_amount / 100 * 2;
            rewardsMasternode = _global_reward_amount / 100 * 98;
            return;
        }

        uint _mnreward = (_global_reward_amount / 100) * getStageOfMining;
        uint _powreward = (_global_reward_amount - _mnreward);

        setBaseRewards(_powreward, _mnreward);
    }

    function setBaseRewards(uint _pow, uint _mn) internal {
        rewardsMasternode = _mn;
        rewardsProofOfWork = _pow;
    }

    /**
     * @dev Executes the masternode flow. Should be called after mining a block.
     */
    function _arrangeMasternodeFlow() internal {
        calculateRewardStructures();
        setMasternodeCandidate();
        miningEpoch++;
    }

    /**
     * @dev Executes the masternode flow. Should be called after mining a block.
     * This is an emergency manual loop method.
     */
    function _emergencyLoop() onlyOwner public {
        calculateRewardStructures();
        setMasternodeCandidate();
        miningEpoch++;
    }

    function masternodeInfo(uint index) public view returns
    (
        address,
        bool,
        uint,
        uint
    )
    {
        return (
            userIndexStruct[index].accountOwner,
            userIndexStruct[index].isActive,
            userIndexStruct[index].storedIndex,
            userIndexStruct[index].startingRound
        );
    }

    function contractProgress() public view returns
    (
        uint epoch,
        uint candidate,
        uint round,
        uint miningepoch,
        uint globalreward,
        uint powreward,
        uint masternodereward,
        uint usercounter
    )
    {
        return (
            masternodeEpoch,
            masternodeCandidate,
            masternodeRound,
            miningEpoch,
            getMiningReward(),
            rewardsProofOfWork,
            rewardsMasternode,
            masternodeCounter
        );
    }

}

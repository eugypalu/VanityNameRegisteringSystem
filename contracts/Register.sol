// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Register is ERC1155 {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    event Commit(address indexed from, bytes32 indexed commitment);
    event Registered(address indexed from, string indexed name, uint256 indexed tokenId, uint256 expirationDate);
    event Renewed(bytes32 indexed name, uint256 indexed expirationDate);
    event Refunded(bytes32 indexed name, uint256 refoundAmount);

    struct Name {
        address owner;
        uint256 expirationDate;
        uint256 amountLocked;
        uint256 tokenId;
    }

    uint public minCommitmentAge;
    uint public maxCommitmentAge;
    uint256 public costPerYear;
    uint8 public maxYear;
    uint8 public waitPeriod;

    mapping(bytes32 => Name) public names;
    mapping(bytes32 => uint) public commitments;
    mapping(uint256 => bytes32) public namesById;

    constructor(uint _minCommitmentAge, uint _maxCommitmentAge, uint256 _costPerYear, uint8 _maxYear, string memory url, uint8 _waitPeriod) ERC1155(url) {
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        costPerYear = _costPerYear;
        maxYear = _maxYear;
        waitPeriod = _waitPeriod;
    }

    /**
     * @notice Allows you to generate the commitment starting from: name, owner and secret
     * @param name Vanity name
     * @param owner Owner of the name
     * @param secret Secret for the commitment
     */
    function makeCommitment(string memory name, address owner, bytes32 secret) pure public returns(bytes32) {
        return keccak256(abi.encodePacked(keccak256(bytes(name)), owner, secret));
    }

    /**
     * @notice save the commitment, so you can record the vanityname
     * @dev prevents front running through a commit/reveal mechanism.
     * @param commitment contains the hash of: vanity name, the owner address and the secret
     */
    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < block.timestamp);
        commitments[commitment] = block.timestamp;
        emit Commit(msg.sender, commitment);
    }

    /**
     * @notice registers a name for a certain period of time, blocking the correct amount of eth. The domain is associated with an erc1155 token that is sent to the user
     * @dev in this situation it is safe to use block.timestamp because the expiration date is very long
     * @param name Vanity name
     * @param owner address of the owner of the name, must match with the commit address
     * @param secret secret key for the commit
     * @param duration for how many years you want to renew the domain
     */
    function register(string memory name, address owner, bytes32 secret, uint8 duration) public payable {
        bytes32 commitment = makeCommitment(name, owner, secret);
        require(commitments[commitment] + maxCommitmentAge >= block.timestamp, "too old"); 
        require(commitments[commitment] + minCommitmentAge <= block.timestamp, "too early");
        require(names[commitment].expirationDate < block.timestamp, "already registered");
        require(duration <= maxYear, "too long");

        uint256 cost = getAmountForDuration(duration);

        require(msg.value >= cost, "not enough value");

        Name storage vanityName = names[commitment];

        if(vanityName.tokenId == 0) {
            _tokenIds.increment();
            _mint(owner, _tokenIds.current(), 1, "");
            vanityName.tokenId = _tokenIds.current();
        } else {
            _safeTransferFrom(vanityName.owner, owner, vanityName.tokenId, 1, "");
        }
        namesById[vanityName.tokenId] = commitment;
        vanityName.owner = owner; 
        vanityName.expirationDate = block.timestamp + getYears(duration);
        vanityName.amountLocked = msg.value;

        uint256 refundValue = msg.value - cost;

        if(refundValue > 0) {
            (bool success, ) = msg.sender.call{value: refundValue}("");
            require(success, "refund failed");
        }

        Registered(msg.sender, name, vanityName.tokenId, vanityName.expirationDate);
    }

    function getAmountForDuration(uint8 duration) public view returns(uint256) {
        return costPerYear * duration;
    }

     /**
     * @notice Renew a domain before its expiration date. the call must be made by the domain owner.
     * @dev If the amount of eth sent is greater than the amount requested, a refund is made.
     * @param vanityName name to renew
     * @param duration for how many years you want to renew the domain
     */
    function renew(bytes32 vanityName, uint8 duration) public payable {
        require(duration <= maxYear, "too long");
        require(!isExpired(vanityName), "is expired");
        names[vanityName].expirationDate += getYears(duration);

        uint256 cost = getAmountForDuration(duration);

        require(cost <= msg.value, "not enough value");
        if(cost < msg.value) {
            (bool success, ) = msg.sender.call{value: msg.value - cost}("");
            require(success, "refund failed");
        }

        emit Renewed(vanityName, names[vanityName].expirationDate);
    }

    /**
     * @notice Check if a domain is expired, checking the expiration date by adding a wait period
     * @dev in this situation it is safe to use block.timestamp because the expiration date is very long
     * @param vanityName name to check
     */
    function isExpired(bytes32 vanityName) public view returns(bool) {
        return block.timestamp > names[vanityName].expirationDate + waitPeriod;
    }

    /**
     * @notice After the expiration date of the domain the blocked amount is unlocked and you can request a refund.
     * @param name domain name for which reimbursement is requested
     */
    function refundEth(bytes32 name) public {
        require(isExpired(name), "not already expired");
        Name storage vanityName = names[name];
        require(vanityName.owner == msg.sender, "not owner");
        vanityName.owner = address(0);
        (bool success, ) = msg.sender.call{value: vanityName.amountLocked}("");
        require(success, "refund failed");
        emit Refunded(name, vanityName.amountLocked);
    }

    /**
     * @notice Allows you to transfer the token that represents ownership of the domain.
     * @param from address of the domain owner
     * @param to recipient's address
     * @param id domain ownership token
     * @param amount amount to be transferred (must be 1)
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );

        names[namesById[id]].owner = to;
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @notice It allows you to burn the token that represents ownership of the domain.
     * @param from address of the domain owner
     * @param id domain ownership token
     * @param amount amount to burn (must be 1)
     */
    function burn(address from, uint256 id, uint256 amount) public {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );

        Name storage vanityName = names[namesById[id]];
        vanityName.owner = address(0);
        vanityName.tokenId = 0;
        _burn(from, id, amount);
    }

    /**
     * @notice Permette di bruciare più token insieme.
     * @dev la quantità deve essere sempre 1, ma è possibile bruciare token diversi insieme
     * @param from address of the domain owner
     * @param ids domain ownership token
     * @param amounts amount to burn (must be 1)
     */
    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) public {
        for(uint i = 0; i < ids.length; i++) {
            Name storage vanityName = names[namesById[ids[i]]];
            vanityName.owner = address(0);
            vanityName.tokenId = 0;
        }
        _burnBatch(from, ids, amounts);
    }

    /**
     * @notice converts the duration into years (1 year consisting of 365 days)
     * @param duration domain duration
     */
    function getYears(uint256 duration) internal pure returns(uint256) {
        return 365 days * duration;
    }

}